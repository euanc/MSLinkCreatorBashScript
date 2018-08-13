#!/bin/bash

#############################################################################################
# mslink.sh v1.0.2
#############################################################################################
# This script is used to create a Windows shortcut (.LNK file)
# Script created based on the doc 
#   http://msdn.microsoft.com/en-us/library/dd871305.aspx
# Updated 8/13/18 to translate from French to English using google translate
#############################################################################################

OPTIONS=$(getopt -q -n ${0} -o hl:o:p -l help,lnk-target:,output-file:,printer-link -- "$@")

eval set -- ${OPTIONS}

IS_PRINTER_LNK=0
while true; do
  case "$1" in
    -h|--help) HELP=1 ;;
    -l|--lnk-target) LNK_TARGET="$2" ; shift ;;
    -o|--output-file) OUTPUT_FILE="$2" ; shift ;;
    -p|--printer-link) IS_PRINTER_LNK=1 ;;
    --)        shift ; break ;;
    *)         echo "Option inconnue : $1" ; exit 1 ;;
  esac
  shift
done

if [ $# -ne 0 ]; then
  echo "Option(s) inconnue(s) : $@"
  exit 1
fi

[ ${#LNK_TARGET} -eq 0 ] || [ ${#OUTPUT_FILE} -eq 0 ] && echo "
Usage :
 ${0} -l target_of_the_lnk_file -o my_file.lnk [-p]

Options :
 -l, --lnk-target               Specifies the target of the shortcut
 -o, --output-file              Save the shortcut to a file
 -p, --printer-link             Generate a network printer shortcut
" && exit 1

#############################################################################################
# Fonctions
#############################################################################################

function ascii2hex() {
	echo $(echo -n ${1} | hexdump -v -e '/1 " x%02x"'|sed s/\ /\\\\/g)
}

function gen_IDLIST() {
        ITEM_SIZE=$(printf '%04x' $((${#1}/4+2)))
        echo '\x'${ITEM_SIZE:2:2}'\x'${ITEM_SIZE:0:2}${1}
}

function convert_CLSID_to_DATA() {
	echo -n ${1:6:2}${1:4:2}${1:2:2}${1:0:2}${1:11:2}${1:9:2}${1:16:2}${1:14:2}${1:19:4}${1:24:12}|sed s/"\([A-Fa-f0-9][A-Fa-f0-9]\)"/\\\\x\\1/g
}

#############################################################################################
# Variables from the official Microsoft documentation
#############################################################################################

HeaderSize='\x4c\x00\x00\x00'							# HeaderSize
LinkCLSID=$(convert_CLSID_to_DATA "00021401-0000-0000-c000-000000000046")	# LinkCLSID
LinkFlags='\x01\x01\x00\x00'							# HasLinkTargetIDList ForceNoLinkInfo 

FileAttributes_Directory='\x10\x00\x00\x00'					# FILE_ATTRIBUTE_DIRECTORY
FileAttributes_File='\x20\x00\x00\x00'						# FILE_ATTRIBUTE_ARCHIVE

CreationTime='\x00\x00\x00\x00\x00\x00\x00\x00'
AccessTime='\x00\x00\x00\x00\x00\x00\x00\x00'
WriteTime='\x00\x00\x00\x00\x00\x00\x00\x00'

FileSize='\x00\x00\x00\x00'
IconIndex='\x00\x00\x00\x00'
ShowCommand='\x01\x00\x00\x00'							# SW_SHOWNORMAL
Hotkey='\x00\x00'								# No Hotkey
Reserved='\x00\x00'								# Non-modifiable value
Reserved2='\x00\x00\x00\x00'							# Non-modifiable value
Reserved3='\x00\x00\x00\x00'							# Non-modifiable value
TerminalID='\x00\x00'								# Non-modifiable value

CLSID_Computer="20d04fe0-3aea-1069-a2d8-08002b30309d"				# Workplace
CLSID_Network="208d2c60-3aea-1069-a2d7-08002b30309d"				# Network Places

#############################################################################################
# Constants found from file analysis lnk
#############################################################################################

PREFIX_LOCAL_ROOT='\x2f'							# Local Disk
PREFIX_FOLDER='\x31\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'		# File folder
PREFIX_FILE='\x32\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'			# File
PREFIX_NETWORK_ROOT='\xc3\x01\x81'						# Root network file server
PREFIX_NETWORK_PRINTER='\xc3\x02\xc1'						# Network Printer

END_OF_STRING='\x00'

#############################################################################################

# On completion remove the final backslash
LNK_TARGET=${LNK_TARGET%\\}

# We separate the root path from the link of the final target
# We also distinguish whether the link is local or network
# We define the value Item_Data according to the case of a network or local link

IS_ROOT_LNK=0
IS_NETWORK_LNK=0

if [[ ${LNK_TARGET} == \\\\* ]]; then
	IS_NETWORK_LNK=1
	PREFIX_ROOT=${PREFIX_NETWORK_ROOT}
	Item_Data='\x1f\x58'$(convert_CLSID_to_DATA ${CLSID_Network})

        TARGET_ROOT=${LNK_TARGET%\\*}
        if [[ ${LNK_TARGET} == \\\\*\\* ]]; then
                TARGET_LEAF=${LNK_TARGET##*\\}
        fi
        if [ ${TARGET_ROOT} == \\ ]; then
                TARGET_ROOT=${LNK_TARGET}
        fi
else
	PREFIX_ROOT=${PREFIX_LOCAL_ROOT}
	Item_Data='\x1f\x50'$(convert_CLSID_to_DATA ${CLSID_Computer})

	TARGET_ROOT=${LNK_TARGET%%\\*}
        if [[ ${LNK_TARGET} == *\\* ]]; then
		TARGET_LEAF=${LNK_TARGET#*\\}
        fi
	[[ ! ${TARGET_ROOT} == *\\ ]] && TARGET_ROOT=${TARGET_ROOT}'\'
fi

if [ ${IS_PRINTER_LNK} -eq 1 ]; then
	PREFIX_ROOT=${PREFIX_NETWORK_PRINTER}
	TARGET_ROOT=${LNK_TARGET}
	IS_ROOT_LNK=1
fi

[ ${#TARGET_LEAF} -eq 0 ] && IS_ROOT_LNK=1

#############################################################################################

# We select the prefix that will be used to display the shortcut icon

if [[ ${TARGET_LEAF} == *.??? ]]; then
	PREFIX_OF_TARGET=${PREFIX_FILE}
	TYPE_TARGET="fichier"
	FileAttributes=${FileAttributes_File}
else
	PREFIX_OF_TARGET=${PREFIX_FOLDER}
	TYPE_TARGET="dossier"
	FileAttributes=${FileAttributes_Directory}
fi

# Targets are converted to binary
TARGET_ROOT=$(ascii2hex "${TARGET_ROOT}")
TARGET_ROOT=${TARGET_ROOT}$(for i in `seq 1 21`;do echo -n '\x00';done) # ok from Vista and higher otherwise the link is considered empty (I have not found any information about this)

TARGET_LEAF=$(ascii2hex "${TARGET_LEAF}")

# We create the IDLIST which represents the core of the LNK file

if [ ${IS_ROOT_LNK} -eq 1 ];then
	IDLIST_ITEMS=$(gen_IDLIST ${Item_Data})$(gen_IDLIST ${PREFIX_ROOT}${TARGET_ROOT}${END_OF_STRING})
else
	IDLIST_ITEMS=$(gen_IDLIST ${Item_Data})$(gen_IDLIST ${PREFIX_ROOT}${TARGET_ROOT}${END_OF_STRING})$(gen_IDLIST ${PREFIX_OF_TARGET}${TARGET_LEAF}${END_OF_STRING})
fi

IDLIST=$(gen_IDLIST ${IDLIST_ITEMS})

#############################################################################################

if [ ${IS_NETWORK_LNK} -eq 1 ]; then
	TYPE_LNK="network"
	if [ ${IS_PRINTER_LNK} -eq 1 ]; then
		TYPE_TARGET="printer"
	fi
else
	TYPE_LNK="local"
fi

echo "Création d'un raccourci de type \""${TYPE_TARGET}" "${TYPE_LNK}"\" avec pour cible "${LNK_TARGET} 1>&2

echo -ne ${HeaderSize}${LinkCLSID}${LinkFlags}${FileAttributes}${CreationTime}${AccessTime}${WriteTime}${FileSize}${IconIndex}${ShowCommand}${Hotkey}${Reserved}${Reserved2}${Reserved3}${IDLIST}${TerminalID} > "${OUTPUT_FILE}"

