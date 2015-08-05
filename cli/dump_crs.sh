#!/bin/bash

function Tabulate()
{
	PREPEND=$1
	SRCFIL=$2
	let RCOUNT=1
	let RMAX=2

	printf "<table width=50%% bgcolor=grey style=\"color:yellow\" cols=${RMAX} link=maroon alink=maroon vlink=maroon>\n"
	printf "<tr>\n"

	while read ONELINE
	do
		__linkee=`printf "<a href=\"${PREPEND}/${ONELINE}\">${ONELINE}</a>"`
		if [ $RCOUNT -lt $RMAX ]; then
			printf "<td>%s</td>" "$__linkee"
			let $((RCOUNT++))
		else
			printf "<td>%s</td></tr>\n<tr>" "$__linkee"
			let RCOUNT=1
		fi
	done < $SRCFIL
	printf "</tr></table>\n"

}



function DealWithZip()
{
	__inFile="$1"

	# -- This is a bit messy
	__Folder=${__inFile%/*}
	__File=${__inFile#*/}

	# -------------------------------------------------
	# Sanity check - the file DOES exists, doesn't it?
	# -------------------------------------------------
	[ ! -e ${__inFile} ] && return 1

	# -------------------------------------------------
	# Is it a zip file?
	# -------------------------------------------------
	if [[ ${__File} =~ "zip" ]]; then
		# -------------------------------------------------
		# It's a zip file - we're going to be busy
		#
		# create a temp folder of the NAME OF THE ZIP file
		# EG: called with lots_of_logs.zip
		#     make a folder called /tmp/temp.3456/lots_of_logs.zip/
		# Then copy the zip file to there with a generic name, unpackme.zip
		# Then unpack it
		# Then construct a manifest of the unpacked files
		# move the "lots_of_logs.zip/" folder BACK to the attachments area
		# and consruct a HTML list of links from the manifect
		# and delete the ZIP file
		# -------------------------------------------------
		__UnpackDir=/tmp/DealWithZip.$RANDOM
		mkdir -p ${__UnpackDir}/${__File}
		pushd ${__Folder} > /dev/null
		mv ${__File} ${__UnpackDir}/${__File}/unpackme.zip
		#cp ${__File} ${__UnpackDir}/${__File}/unpackme.zip
		pushd ${__UnpackDir}/${__File} > /dev/null
		unzip -qq unpackme.zip
		rm -f unpackme.zip
		cd ..
		find ${__File}  | grep '/' | sort > ._unpack.list
		Tabulate "${__Folder}" ._unpack.list
		popd  > /dev/null
		mv ${__UnpackDir}/${__File} .
		rm -rf ${__UnpackDir}
		popd > /dev/null
		return 1
	else

		return 0
	fi
}

# ----------------------------------------------
# Only dump this object if the name glob matches
# PARAM objectname
# PARAM name string (eg ".log")
# ----------------------------------------------

function DumpAttrIfNameMatches()
{
	local AttrONAME="$1"
	local NameSubStr="$2"
	local dumpFolder=""
	local coment=""
	local ffAttrName="" # FileFreindly name, no spaces, that kinda thing

	# ---------------------------------------------------------
	# Must quote object name because it is unusual for synergy
	# in that it is two-part, for example
	# "attachment_DBASENAME#1649 1310561341~1:binary:DBASENAME#1"
	# (normal object name would be apple_pie.cpp~1:c++:DBASENAME#1)
	# ---------------------------------------------------------
	ffattrName=$(ccm attr -s attachment_name "${AttrONAME}" | sed 's/[ |#|!]/_/g')
	if [[ ${ffattrName} =~ ${NameSubStr} ]]; then
		echo "	*** Success!! Dumping ${ffattrName}" >&2

		# Source file name
		dumpFolder="${ATTACH_DIR}/${ffattrName}"
		[ -e "${dumpFolder}" ] && dumpFolder=${ffattrName}.$RANDOM

		# ---- substring match; dump file & echo a href
		SRC_FILE=$(ccm attr -s source "${AttrONAME}") # This is the actual file in the Synergy repo.
		cp ${SRC_FILE} ${dumpFolder}

		  printf "<tr>"
		  printf "<td><a href=\"./%s\">%s</a>\n" "${dumpFolder}" "${ffattrName}"
		  DealWithZip ${dumpFolder}
		  printf "</td>"
		  printf "<td>"
		  # Get attachment comment
		  ccm attr -s comment "${AttrONAME}"
		  printf "</td>"
		  printf "</tr>"
	else
		# ---- substring no match; Just echo file name
		printf "${ffattrName}<br>\n"
	fi
}

# --------------------------------------------
# DumpCRattachements
# 	Params 	created_in
# 	Params 	problem_number
# 	Params 	filter
# --------------------------------------------
function DumpCRattachements()
{
	local_MIN=$1
	local_CRN=$2
	TFILE=/tmp/tattach.$RANDOM


	local_ONAME=$(ccm query -t problem -n problem${local_CRN} "created_in='${local_MIN}'" -u -f %objectname)
	echo "DumpCRattachements ${local_MIN}#${local_CRN} - [${local_ONAME}]" >&2
	ccm query "is_attachment_of('${local_ONAME}')" -u -f "DumpAttrIfNameMatches \"%objectname\" " > ${TFILE}
	if [ $(cat $TFILE | wc -l) -gt 0 ]; then
		# -----------------------------------------
		# We got some attachments!
		# At this stage we don't know their names, or if we've dumped them before.
		# What we DO know is that we're either being -f Forced to redump all CR's, or the CR has been
		# modified since we last "saved" it.  We don't know if the attachments have changed or if they are the same
		# so the crude solution is to *delete* the attachement subdir and recreate it.
		# All we're doing is a CP from the database cache, so it's as "light" as it could be.
		# We could do ln's I guess, but would prob run into permissions issues
		# -----------------------------------------
		if [ -d ${ATTACH_DIR} ]; then
			rm -rf ${ATTACH_DIR}
		fi
		mkdir ${ATTACH_DIR}
		# ------------------------------------------
		# okay, re-save
		# ------------------------------------------

		#cat ${TFILE} >&2
		# ----
		printf "<tr><th><strong>Attached files</strong></th><td>\n"
		printf "<table width=100%% bgcolor=grey style=\"color:yellow\ border=\"0\">"
		source ${TFILE}
		printf "</table>"
		printf "</td><tr>\n"
	fi
	[ -e ${TFILE} ] && rm ${TFILE}
}

function CCMstart_path()
{
	export CCM_PATH="${1}"
	if [ -n "$1" -a -d "$1" ]; then
		TMPF=/tmp/ccmstartlog.$RANDOM
		export CCM_ADDR=$(nice -n 10 ccm start -m -d "${CCM_PATH}" -q -nogui -r build_mgr -h ${CCM_HOST} 2> ${TMPF})
		echo "# Started at ${DMT} [by $0]" >> ${TMPF}

		if [ "${CCM_ADDR}" == "" ]; then
			#echo "ERROR!! Synergy start up failure :-("
			#T_CAT ${TMPF}
			return 2
		fi
		rm ${TMPF}
		export CCM_DBID=`ccm dcm -show -dbid`
		return 0
	else
		echo "ERROR!! Can't find specified dbase [${CCM_PATH}]"
		return 2
	fi
}

echo "Demo using CR  MYDBASE#456"
CCMstart_path /path/to/MYDBASE
DumpCRattachements "MYDBASE" "456"
ccm stop