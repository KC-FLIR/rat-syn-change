###########################################################
## connection Class
###########################################################

package connection::csOps71;

$VERSION = "1.0";

use strict;
use warnings;

use ChangeSynergy::csapi;
use ChangeSynergy::apiObjectVector;
use ChangeSynergy::apiData;
use folderOps::crList;

use strict;
use warnings;



sub new($)
{
	my $class= shift;
	## specify the dbase you're connecting to when you instatiate
	my $dbase= shift;

	my $csapi;
	my $csglobals;
	my $auser;


	# Initialize data as an empty hash
	my $self = {};
	$csglobals = new ChangeSynergy::Globals();
	$csapi     = new ChangeSynergy::csapi();

	print "Using CCM71";
	$csapi->setUpConnection("<INSERT SERVER URL>");



	if (-d $dbase)
	{
		# autofix user's password is a shell environment variable
		# user-password-role-dbasename
		$auser=$csapi->Login("<USER-ACCOUNT>","<USER-PASSWORD>","Lead",$dbase);
	}
	else
	{
		die "connection::csOps.pm: Unable to find the database [$dbase]\n";
	}


	$self->{NAME} = undef;
	$self->{CMD}= undef;
	$self->{RETVAL}=[];
	$self->{CSIF}=$csapi;
	$self->{AUSR}=$auser;
	$self->{GLOB}=$csglobals;
	$self->{DBASE}=$dbase;


	bless ($self,$class);
	return $self;
}







sub getRoot()
{
	my $self = shift;
	return $self->{CSIF};
}


sub getUser()
{
	my $self = shift;
	return $self->{AUSR};
}




sub submitIssue()
{
	my $self = shift;

	#$self->{CSIF}->->CopyCRData($self->{AUSR}, "100", "START_HERE2issue_open");



	eval
	{
		my $tmp = $self->{CSIF}->SubmitCRData($self->{AUSR}, "START_HERE2issue_open");

		my $i;
		my $j = $tmp->getDataSize();

		for($i=0;$i<$j;$i++)
		{
			if($tmp->getDataObject($i)->getRequired())
			{
				$tmp->getDataObject($i)->setValue("I must supply a value here to successfully complete a submit...");
			}
		}

		$tmp->getDataObjectByName("problem_synopsis")->setValue("I submitted this through the csapi");
		$tmp->getDataObjectByName("problem_description")->setValue("Yes, isn't this great!!!!");
		$tmp->getDataObjectByName("severity")->setValue("Showstopper");
		$tmp->getDataObjectByName("submitter")->setValue("AutoSubmit");
		$tmp->getDataObjectByName("issue_type")->setValue("Defect");

		$tmp->getDataObjectByName("crstatus")->setValue($tmp->getTransitionLink(0)->getToState());

		my $tmpstr = $self->{CSIF}->SubmitCR($self->{AUSR}, $tmp);

		printf "Submit result : [%s]\n",$tmpstr;

	};

	if ($@)
	{
		print $@;
	}

}




## parameters
## scalar 	cr_id	<dbid>#<crid>
## scalar	attr	attribute name
##
## example 	getAttribute ( Displays#1,"crstatus")
##
sub getAttribute($$)
{
	my $self = shift;

	my $crID   = shift;
	my $attr   = shift;


	print "Looking for attribute [".$attr."] on cr [".$crID."]\n";
	my $tmp = $self->{CSIF}->AttributeModifyCRData($self->{AUSR}, $crID, $attr);
	#my $tmpstr = $tmp->getXmlData();

	my $tmpstr = $tmp->getDataObjectByName($attr);
	return $tmpstr;
}


## parameters
## scalar 	cr_id	<dbid>#<crid>
## scalar	problem number	attribute name
##
## returns string composition - "cvid,name,comment"
##
## example 	getCRAttachmentDetails ( "MyCRdbase#1")
##
## Obviously assumes a DCM initialised dbase with the DCM name as a prepend to the CR number
##
sub getCRAttachmentDetails($)
{
	my $self = shift;
	my $crID = shift;
	my @bits = split /#/,$crID;
	my $retString;
	my $reportFormat="cvid|attachment_name|comment";
	my $apiQueryData;
	my $objectVector;
	my $objectData;
	my $reportLineCtr;
	my $reportItemCtr;

	my $CRobject = "problem".$bits[1]."~1:problem:".$bits[0];
	my $CRquery  = "is_attachment_of('".$CRobject."')";

	$apiQueryData = $self->{CSIF}->QueryStringData($self->{AUSR}, "Basic Summary","$CRquery","$reportFormat");

	for ($reportLineCtr=0;$reportLineCtr<$apiQueryData->getDataSize();$reportLineCtr++)
	{
		$objectVector = $apiQueryData->getDataObject($reportLineCtr);
		for ($reportItemCtr=0;$reportItemCtr<$objectVector->getDataSize();$reportItemCtr++)
		{
			$objectData = $objectVector->getDataObject($reportItemCtr);
			$retString .= $objectData->getValue().",";
		}
		$retString .= "\n";
	}
	return $retString;
}



##############################
# Supply CVID
# Supply folder
##############################
sub getAttachment($$)
{
	my $self = shift;
	my $cvid = shift;
	my $filename = shift;
	my $suffix_count = 2;
	my $suffix_string = "";
	my $target_filename;

	my $data= $self->{CSIF}->DatabaseGetObject($self->{AUSR}, $cvid);

	$target_filename=sprintf("%s",$filename);
	while ( -e "$target_filename" )
	{
		printf "csOps.pm::getAttachment - Most odd, [%s] already exists\n",$target_filename;
		$suffix_string=sprintf(".%d",$suffix_count);
		$target_filename=sprintf("%s%s",$filename,$suffix_string);
		$suffix_count++;
	}


	open(ATTACHMENT,">$target_filename") or die "Unable to create [$target_filename]";
	print ATTACHMENT $data->getResponseByteData();
	close ATTACHMENT;

	return $target_filename;
}







## parameters
##
## scalar 	qryString
## scalar	formatString
##
## returns string composition - "formatString"
##
## example 	doQry ("(product_name='toaster')","problem_number|priority")
##
##
sub doQrySep($$$)
{
	my $self = shift;
	my $qryString = shift;
	my $reportFormat= shift;
	my $seperator=shift;

	my $dingle=$qryString;

	my $retString;
	my $apiQueryData;
	my $objectVector;
	my $objectData;
	my $reportLineCtr;
	my $reportItemCtr;
	my $reportDataSize;

	$apiQueryData = $self->{CSIF}->QueryStringData($self->{AUSR}, "Basic Summary",$dingle,"$reportFormat");

	eval
	{
		$reportDataSize=$apiQueryData->getDataSize();
	};

	if ($@)
	{
		print "error:\n";
		print $@;
		die "CSAPI failure\n";
	}

	for ($reportLineCtr=0;$reportLineCtr<$reportDataSize;$reportLineCtr++)
	{
		$objectVector = $apiQueryData->getDataObject($reportLineCtr);
		for ($reportItemCtr=0;$reportItemCtr<($objectVector->getDataSize());$reportItemCtr++)
		{
			$objectData = $objectVector->getDataObject($reportItemCtr);
			$retString .= $objectData->getValue().$seperator;
		}
		$retString .= "\n";
	}

	return $retString;
}



## parameters
##
## scalar 	qryString
## scalar	formatString
##
## returns string composition - "formatString"
##
## example 	doQry ("(product_name='toaster')","problem_number|priority")
##
##
sub doQry($$)
{
	my $self = shift;
	my $qryString = shift;
	my $reportFormat= shift;

	printf "doQry [%s] [%s]\n",$qryString,$reportFormat;

	my $answer= doQrySep("$qryString","$reportFormat",",");


	return $answer;
}





## parameters
## scalar 	cr_id	<dbid>#<crid>
## scalar	attr	attribute name
##
## example 	getAttribute ( Displays#1,"crstatus")
##
sub getDefectAttachments($)
{
	my $self = shift;

	my $crID   = shift;
	#my $attr   = shift;


	print "Looking up data on  on cr [".$crID."]\n";
	my $tmp = $self->{CSIF}->ModifyCRData($self->{AUSR}, $crID, "CRDetail");
	my $tmpstr = $tmp->getXmlData();

	#my $tmpstr = $tmp->getDataObjectByName($attr);
	return $tmpstr;
}




## parameters
## scalar 	cr_id	<dbid>#<crid>
## scalar	attr	attribute name
##
## example 	getAttribute ( Displays#1,"crstatus")
##
sub getAttrIBM($$)
{
	my $self = shift;

	my $crID   = shift;
	my $attr   = shift;
	my $retval="no retval";


	print "GetAttr: Looking for attribute [".$attr."] on cr [".$crID."]\n";
	my $apiObjectVector = $self->{CSIF}->GetCRData($self->{AUSR}, $crID, "$attr");

	my $apiData = $apiObjectVector->getDataObjectByName("$attr");
	$retval=$apiData->getValue();
	return $retval;

}


## parameters
## scalar 	cr_id	<dbid>#<crid>
## scalar	attr	attribute name
##
## example 	getAttribute ( Displays#1,"crstatus")
##
sub setAttrIBM($$$)
{
	my $self = shift;

	my $crID   = shift;
	my $attr   = shift;
	my $newVal = shift;
	my $retval="no retval";
	my $auditLine= sprintf("csOps::setAttrIBM: setting for attribute [%s] on cr [%s] to [%s]",$attr,$crID,$newVal);


	crList::auditLog($auditLine);

	my $apiObjectVector = $self->{CSIF}->GetCRData($self->{AUSR}, $crID, "$attr");
	my $apiData = $apiObjectVector->getDataObjectByName("$attr");
	$retval=$apiData->setValue("$newVal");
	$self->{CSIF}->ModifyCR($self->{AUSR},$apiObjectVector);
	return $retval;

}


#########################################################################################################
#########################################################################################################


sub addTaskToCR($$)
{
	my $self = shift;

	my $taskID = shift;
	my $crID   = shift;

	print "in Addtask TASK[".$taskID."] CR[".$crID."]\n";
	my $tmpstr = $self->{CSIF}->CreateRelation($self->{AUSR},"TRUE",$taskID,$crID,"associated_task",$self->{GLOB}->{CCM_PROBLEM_TASK});

}
#########################################################################################################
# users # users # users # users # users # users # users # users # users # users # users # users # users #
#########################################################################################################

#
# Fields:
# 1	userlist ($ list with "Fsmith,Bsmith,Csmith" etc)
# 2 roles 	 ("resolver|developer")
#
# Asssumes current dbase
sub AddUserList($$)
{
	my $self   = shift;
	my $users  = shift;
	my $roles  = shift;
	my @newCSusers;
	my @newPLAINusers;
	my $compUser;

	@newPLAINusers=split(",",$users);

	eval
    {

    	my $i;
    	my $j=$#newPLAINusers;
	my $password="test_password";
	$j++;

    	for($i=0;$i<$j;$i++)
    	{
		# Generate a list of bash commands to add thse users to the server, if necessary

		push @newCSusers, new ChangeSynergy::apiUser($newPLAINusers[$i],$password,$roles,$self->{DBASE});
		if (! (-d "/home/$newPLAINusers[$i]"))
		{
			printf ("adduser -s /bin/bash %s\n",$newPLAINusers[$i]);
		}

    	}

    	my $tmpstr = $self->{CSIF}->AddUsers($self->{AUSR}, \@newCSusers, $j);
    };

   	if ($@)
   	{
   		print $@;
   	} else
	{
		## <-- Yay! Success.
		my $logLine="";
		my $num=$#newPLAINusers;
		$num++;
		$logLine=sprintf("AddUser,adding %d users to database [%s]",$num,$self->{DBASE});
		crList::auditLog($logLine);
		$logLine=sprintf("AddUser,Roles [%s]",$roles);
		crList::auditLog($logLine);
		$logLine=sprintf("AddUser,Names [%s]",$users);
		crList::auditLog($logLine);
	}




}























