#!/usr/bin/perl -w

#Copyright (c) 2014, Stargazy Studios
#All Rights Reserved

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#xmlInjectElementCount will search an input XSD schema for Types with Processing 
#Instruction named with a specified keyword (default 'elementCount'). In a conforming XML 
#document, Elements of the name specified in the PI, also in the scope specified, are 
#counted. The count is then injected into the parent Element of the PI, into an attribute 
#named in the PI.

#Processing Instruction required parameters:
#	syntax: name=[value[|alt_value]*]
#		elementName=[.+]:			The name of the Elements that should be counted.
#
#		attributeName=[.+]: 		The name of the Attribute to store the count.
#
#		scope=["children"]:			Only Elements in the specified scope will be counted.
#											-children: count only direct descendants of 
#											the parent Element of the Processing 
#											Instruction.

#TODO: allow for an Element Type to be specified, instead of a name.

use strict;
use Getopt::Long;
use XML::LibXML;
use File::Basename;
use Data::Dumper;

sub checkTypeAndExpandElement{
	my ($element,$elementPath,$xmlData,$uidTypesHashRef,$uidElementsHashRef) = @_;
	
	if ($element->hasAttribute("type")){
		my $elementType = $element->getAttribute("type");
		
		#if the element's complexType matches a uid keyword
		if (exists $$uidTypesHashRef{$elementType}){
		
			#check if this element has already been expanded, and if so terminate
			if (exists $$uidElementsHashRef{$elementPath}){
				return;
			}
			
			#otherwise, add the element path to the hash
			else{
				#DEBUG
				#print "Storing $elementPath\n";
				$$uidElementsHashRef{$elementPath} = $elementType;
			}
		}
		
		#process child elements
		foreach my $complexType ($xmlData->findnodes('/xs:schema/xs:complexType[@name="'.$elementType.'"]')){
			foreach my $childElement ($complexType->findnodes("./xs:sequence/xs:element")){
				if ($childElement->hasAttribute("name")){
					my $childElementPath = $elementPath."/".$childElement->getAttribute("name");
					checkTypeAndExpandElement($childElement,$childElementPath,$xmlData,$uidTypesHashRef,$uidElementsHashRef);
				}
			}
		}
	}
}

sub searchElements{
	#Search the passed hash of XSD elements for Complex Type keywords, expanding any that
	#are found to continue the search. As the name of an element can be duplicated within 
	#different types, the hierarchy of the path to the name must be stored along with it.
	#XML element names can not contain spaces, so this character can be used to delineate
	#members of the hierarchy.
	 
	#Loop detection can be made by comparing the hierarchy path element names to the 
	#current one under consideration.
	
	my ($xmlData,$uidTypesHashRef,$uidElementsHashRef) = @_;

	#iterate through all elements
	foreach my $element ($xmlData->findnodes("/xs:schema/xs:element")){
		#check element type against list of Type keywords
		if ($element->hasAttribute("name")){
			#DEBUG
			#print "Processing ".$element->getAttribute("name")."\n";
			checkTypeAndExpandElement($element,"/".$element->getAttribute("name"),$xmlData,$uidTypesHashRef,$uidElementsHashRef);
		}
	}
}

my $xsdIn = '';
my $xmlIn = '';
my $outDir = '';
my $elementCountPI = 'elementCount'; #keyword to denote uid Processing Instruction

GetOptions(	'xsdIn=s' => \$xsdIn,
			'xmlIn=s' => \$xmlIn,
			'outDir=s' => \$outDir,
			'elementCountPI=s' => \$elementCountPI
);

#check outDir finishes with a slash if it contains one
if($outDir =~ /^.*[\/].*[^\/]$/){$outDir = "$outDir/";}
else{if($outDir =~ /^.*[\\].*[^\\]$/){$outDir = "$outDir\\";}}

my $parserLibXML = XML::LibXML->new();

#parse xsd schema to find keywords, storing array of Type names that contain the uid key
if(-e $xsdIn && -e $xmlIn ){
	my $xmlData = $parserLibXML->parse_file($xsdIn);
	
	if($xmlData){
		my %countStoreTypes;
		
		#iterate through all complexTypes in the schema
		foreach my $type ($xmlData->findnodes('/xs:schema/xs:complexType[processing-instruction("'.$elementCountPI.'")]')){
			if($type->hasAttribute("name")){
				foreach my $childNode ($type->getChildNodes){
					if(	$childNode->nodeType eq XML_PI_NODE && 
						$childNode->nodeName eq $elementCountPI){
						
						my $nodeDataString = $childNode->getData();
						$nodeDataString =~ s/"//g; #remove quotation marks
						
						#store all PI instruction parameters, allowing for multiple PIs by using an array
						push(@{$countStoreTypes{$type->getAttribute("name")}},{split(/[ =]/,$nodeDataString)});
					}
				}			
			}
		}
	
		#DEBUG		
		#print Dumper(%uidTypes);
		
		#on a second pass, identify which element names are of the Type to store a count
		#attribute
		#-process xs:complexType:
		#-process xs:element:
		my %countStoreElements;
		my $countStoreElementsHashRef = \%countStoreElements;
		
		#recursively search for elements with keyword types and store hierarchy paths
		searchElements($xmlData,\%countStoreTypes,$countStoreElementsHashRef);

		#DEBUG check countStoreElements for correctness
		#print Dumper($countStoreElementsHashRef);
		
		#parse XML document to find named Elements, counting them and injecting the count
		$xmlData = $parserLibXML->parse_file($xmlIn);		
		if($xmlData){			
			#inject counts in XMLData
			foreach my $elementPath (keys %{$countStoreElementsHashRef}){
				
				my $countStoreElementType = $countStoreElements{$elementPath};
				
				foreach my $countStoreElement ($xmlData->findnodes($elementPath)){
					foreach my $piParamsHashRef (@{$countStoreTypes{$countStoreElementType}}){					
						if(	exists $piParamsHashRef->{"elementName"} &&
							exists $piParamsHashRef->{"attributeName"} &&
							exists $piParamsHashRef->{"scope"}){

							#count all Elements of the name and scope specified
							my $elementCount = 0;
							if($piParamsHashRef->{"scope"} eq "children"){
								$elementCount = @{$xmlData->findnodes($elementPath."/".$piParamsHashRef->{"elementName"})};
								#store the count in the named attribute
								$countStoreElement->setAttribute($piParamsHashRef->{"attributeName"}, $elementCount);
							}
							else{
								print STDERR "WARNING: \"scope\" mode specified in Processing Instruction ".
								"is not supported. IGNORING\n";
							}
						}	
						else{
							print STDERR "ERROR: missing data for Processing Instruction, ".
							"please ensure \'elementName\', \'attributeName\' & \'scope\' ".
							"are set. EXIT\n";
							exit 1;
						}
					}
				}
			}
			
			#output XMLData to file
			my $outFilePath = '';
			if($outDir){$outFilePath = $outDir.fileparse($xmlIn);}
			else{$outFilePath = $xmlIn;}
			$xmlData->toFile($outFilePath);
		}
		else{
			print STDERR "ERROR: xmlIn($xmlIn) is not a valid xml file. EXIT\n";
			exit 1;
		}
	}
	else{
		print STDERR "ERROR: xsdIn($xsdIn) is not a valid xml file. EXIT\n";
		exit 1;
	}
}
else{
	print STDERR "ERROR: options --xsdIn --xmlIn are required. EXIT\n";
	exit 1;
}