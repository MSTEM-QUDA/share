#!/usr/bin/perl -s

my $Help     = ($h or $help); undef $h; 
my $Commands = $c;            undef $c;
my $Force    = $f;            undef $f;

use strict;

&print_help if $Help or not @ARGV;

my $ERROR   = "ERROR in XmlToF90.pl:";
my $WARNING = "WARNING in XmlToF90.pl:";

die "$ERROR cannot use -f and -c switches together!\n" if $Force and $Commands;
die "$ERROR input file argument is missing!\n" unless @ARGV;

require 'share/Scripts/XmlRead.pl';

my $InputFile  = $ARGV[0];
my $OutputFile = $ARGV[1];

open(IN, $InputFile) or die "$ERROR could not open input file $InputFile\n";
my $Input = join('',<IN>);
close(IN);

my $Update = ($OutputFile and -f $OutputFile and not $Force);

my $NewFile = ($OutputFile and not ($Update or $Commands));

my $Indent     = (' ' x 7);  # initial indentation for case statements
my $Indent1    = (' ' x 3);  # incremental indentation
my $IndentCont = (' ' x 5);  # indentation for continuation lines

my $SrcCode;            # F90 code produced by the script
my $SrcDecl;            # Declaration of command parameters
my $SrcIndex;           # Declaration of indexes used in loops
my $SrcCase;            # The case statements reading in the parameters
my $iPart;              # part index for multi-part parameters
my $ForeachName;        # name of the index variable in a foreach loop
my $ForeachValue;       # value of the index variable in a foreach loop
my %VariableType;       # Hash for variable types
my %DefaultValue;       # Hash for default values

# put in UseStrict
$VariableType{"UseStrict"} = "logical";
$DefaultValue{"UseStrict"} = "T";

my $Xml = &XmlRead($Input); # XML tree data structure created from XML text

&process_xml($Xml);

if($NewFile){
    my $Module = $OutputFile;
    $Module = $1 if $Module =~ /\/([^\/]+)$/;  # remove path
    $Module =~ s/\..*$//;                          # remove extension

    $SrcCode = 
"module $Module

  use ModReadParam, ONLY: i_session_read, read_line, read_command, read_var
  use ModUtilities, ONLY: split_string

  implicit none

  character(len=*), parameter:: NameMod = '$Module'

$SrcDecl

contains

  subroutine set_parameters

    character (len=100) :: NameCommand, StringPart_I(100)
    integer :: iSession, nStringPart
    logical :: UseStrict
$SrcIndex

    character(len=*), parameter:: NameSub = NameMod//'::set_parameters'
    !-------------------------------------------------------------------------
    iSession = i_session_read()
    do
       if(.not.read_line() ) EXIT
       if(.not.read_command(NameCommand)) CYCLE
       select case(NameCommand)
$SrcCase
       case default
          !if(iProc==0) then
          write(*,*) NameSub // ' WARNING: unknown command ' // &
               trim(NameCommand),' !'
          if(UseStrict)call CON_stop('Correct PARAM.in!')
          !end if
       end select
    end do

  contains

    logical function is_first_session()
      is_first_session = iSession == 1
      if(iSession > 1)then
         ! if(iProc==0) then
         write(*,*) NameSub // ' WARNING: command ',trim(NameCommand), &
              ' can be used in first session only!'
         if(UseStrict)call CON_stop('Correct PARAM.in!')
         ! end if
      end if
    end function is_first_session

  end subroutine set_parameters

end module $Module
";
}else{
    $SrcCode = "$SrcDecl"."  !".("-" x 75).$SrcCase;
}
if($OutputFile){
    open(OUT, ">$OutputFile") or 
	die "$ERROR could not open output file $OutputFile\n";
    print OUT $SrcCode;
    close(OUT);
}else{
    print $SrcCode;
}

exit 0;

##############################################################################
sub process_xml{

    # recursive subroutine that processes the XML file

    my $content = shift;

    foreach my $element (@$content){

        next if $element->{type} eq 't'; # Ignore elements of type text

	my $name = lc( $element->{"name"} );

	if($name eq 'commandlist'){
	    &process_xml($element->{content});
	}elsif($name eq 'commandgroup'){
	    my $Name = $element->{attrib}->{name};
	    # Remove previous command comment if there were no parameters
	    $SrcDecl =~ s/  ! \"\#\w+\"\n$//;
	    $SrcDecl .= "\n  ! >>> $Name <<<\n";
	    $SrcCase .= "\n".$Indent."! >>> $Name <<<\n\n";
	    &process_xml($element->{content});
	}elsif($name eq 'command'){
	    my $Attrib = $element->{attrib};
            my $Name   = "\"\#$Attrib->{name}\"";
	    my $Alias  = $Attrib->{alias};
	    foreach my $Alias (split ",", $Attrib->{alias}){
		$Name .= ", \"\#$Alias\"";
	    }
	    # Remove previous command comment if there were no parameters
	    $SrcDecl =~ s/  ! \"\#\w+\"\n$//;
	    # Add new comment
	    $SrcDecl .= "  ! $Name\n";
	    $SrcCase .= $Indent."case($Name)\n";
	    $Indent .= $Indent1;
	    my $If = $Attrib->{if};
	    if($If =~ /IsFirstSession/){
		$SrcCase .= $Indent."if(.not.is_first_session())CYCLE\n";
	    }
	    &process_xml($element->{content});
	    $Indent =~ s/$Indent1//;
	}elsif($name eq 'parameter'){
	    my $Attrib = $element->{attrib};
	    my $Name   = perl_to_f90($Attrib->{name});
	    my $Type   = $Attrib->{type};
	    my $Case   = $Attrib->{case};
	    my $If     = perl_to_f90($Attrib->{if});

            if($Type eq "string"){
		my $Length = $Attrib->{length};
		$Type = "character(len=$Length)" if $Length;
	    }

	    # Store variable
	    &add_var($Name, $Type, $Attrib->{default});

	    # Create line
	    $SrcCase .= $Indent."if($If) &\n".$IndentCont if $If;
	    $SrcCase .= $Indent."call read_var('$Name', $Name)\n";

	    $SrcCase =~ s/\)\n$/, IsUpperCase=.true.)\n/ if $Case eq "upper";
	    $SrcCase =~ s/\)\n$/, IsLowerCase=.true.)\n/ if $Case eq "lower";


	    if($Type eq "strings"){
		my $MaxPart = $Attrib -> {max};
		$SrcCase .= $Indent . "call split_string" . 
		    "($Name, $MaxPart, StringPart_I, nStringPart)\n";
		$iPart = 0;
		&process_xml($element->{content});
	    }
	}elsif($name eq 'part'){
	    my $Name = $element->{attrib}->{name};
	    &add_var($Name, "string");
	    $iPart++;
	    $SrcCase .= $Indent."$Name = StringPart_I($iPart)\n";
	}elsif($name eq 'if'){
	    my $Expr = perl_to_f90($element->{attrib}->{expr});
	    $SrcCase .= $Indent."if($Expr)then\n";
	    $Indent .= $Indent1;
	    &process_xml($element->{content});
	    $Indent =~ s/$Indent1//;
	    $SrcCase .= $Indent."end if\n";
	}elsif($name eq 'for'){
	    my $Attrib = $element->{attrib};
	    my $From  =  perl_to_f90($Attrib->{from});
	    my $To    =  perl_to_f90($Attrib->{to});
	    my $Index = (perl_to_f90($Attrib->{name}) or "i");

	    # Declare index variable
	    $SrcIndex .= "    integer :: $Index\n" 
		unless $SrcIndex =~ /integer :: $Index\b/i;

	    $SrcCase .= $Indent."do $Index = $From, $To\n";
	    $Indent .= $Indent1;
	    &process_xml($element->{content});
	    $Indent =~ s/$Indent1//;
	    $SrcCase .= $Indent."end do\n";
	}elsif($name eq 'foreach'){
	    my $Attrib = $element->{attrib};
	    $ForeachName = $Attrib->{name};
	    foreach (split(/,/, $Attrib->{values})){
		$ForeachValue = $_;
		&process_xml($element->{content});
	    }
	    $ForeachName = ''; $ForeachValue = '';
	}
    }
}

###############################################################################

sub perl_to_f90{

    $_ = shift;

    # replace special variables provided by the CheckParam.pl script
    s/\$_command/NameCommand/ig;
    s/\$_namecomp/NameComp/ig;

    # replace foreach variable with actual value
    s/\$$ForeachName/$ForeachValue/g if $ForeachName;

    # remove all dollar signs from variable names
    s/\$//g;

    # convert relation operator
    s/ eq / == /g;
    s/ ne / \/= /g;
    s/ and / .and. /g;
    s/ or / .or. /g;
    s/ != / \/= /g;
    s/\bnot /.not. /g;

    # replace string matching (this is not quite right!)
    s/(\w+)\s*=~\s*\/([^\/]+)\/i?/index($1, "$2") > 0/g;

    s/(\w+)\s*\!~\s*\/([^\/]+)\/i?/index($1, "$2") < 1/g;

    # Remove \b from patterns (this is not quite right!)
    s/\\b//g;

    return $_;
}

###############################################################################

sub add_var{

    my $Name  = shift;
    my $Type  = shift;
    my $Value = shift;

    my $name = lc($Name); # F90 is not case sensitive

    # Check if variable name has already occured or not
    my $Type2 = $VariableType{$name};
    if($Type2){
	# Check if types agree
	if($Type ne $Type2){
	    warn "$WARNING: variable $Name has types $Type and $Type2\n";
	    $SrcDecl .= "!!! $Type :: $Name was declared above with $Type2\n";
	    return;
	}
	# Check if default values agree
	my $Value2 = $DefaultValue{$name};
	if(length($Value) and length($Value2) and ($Value ne $Value2)){
	    warn "$WARNING: variable $Name has default values ".
		"$Value and $Value2\n";
	    $SrcDecl .= "!!! $Type :: $Name = $Value ".
		"was declared above with value $Value2\n";
	    return;
	}
	$SrcDecl .= "  ! $Type :: $Name has been declared above\n";
	return;
    }

    # replace variables with their default values if possible
    while($Value =~ /\$(\w+)/){
	my $Value2 = $DefaultValue{lc($1)};
	$Value =~ s/\$(\w+)/$Value2/ if $Value2;
    }

    # Store variable
    $VariableType{$name} = $Type;
    $DefaultValue{$name} = $Value;

    $Type =~ s/strings?/character(len=100)/;

    # Fix value
    $Value =~ s/T/.true./ if $Type eq "logical";
    $Value =~ s/F/.false./ if $Type eq "logical";
    $Value =  "'$Value'" if $Type =~ /character/ and length($Value);
    $Value .= ".0" if $Type eq "real" and $Value =~ /^\d+$/;

    # Add declaration
    if(length($Value)){
	$SrcDecl .= "  $Type :: $Name = $Value\n";
    }else{
	$SrcDecl .= "  $Type :: $Name\n";
    }
}

###############################################################################
#BOP
#!ROUTINE: XmlToF90.pl - generate F90 source from XML definitions of input parameters
#!DESCRIPTION:
# Generate F90 source code based on the XML definitions of the
# input parameters typically found in the PARAM.XML files.
# This script allows to store the parameter descriptions in a single XML file
# which is suitable for automated parameter checking, manual and GUI 
# generation, as well as generating the F90 code that reads in the parameters.
# The specific format of the PARAM.XML files is described by the
# share/Scripts/CheckParam.pl script and the manual.
#
#!REVISION HISTORY:
# 05/27/2008 G.Toth - initial version
#EOP
sub print_help{

    print 
#BOC
"Purpose:

   Convert XML description of input commands into F90 source code.

Usage:

   XmlToF90 [-h] [-f | -c=COMMANDS] infile [outfile]

-h          This help message

-c=COMMANDS COMMANDS is a comma separated list of commands to be transformed
            from XML to F90. Default is transforming all the commands.

-f          Force creating a new output file even if it already exists. 
            This flag cannot be combined with the -c=COMMAND switch.
            Default is to update the (selected) commands only in an existing
            file.

infile      Input XML file.

outfile     Output F90 file. Default is writing to STDOUT.

Examples:

            Generate F90 source code for a few commands and write to STDOUT:

share/Scripts/XmlToF90.pl -c=MAGNETICAXIS,ROTATIONAXIS Param/PARAM.XML

            Update all commands in an existing F90 source file

share/Scripts/XmlToF90.pl PARAM.XML src/set_parameters.f90"
#EOC
    ,"\n\n";
    exit 0;
}
