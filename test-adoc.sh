#!/bin/bash

# test-adoc.sh - test an AsciiDoc file and report possible issues
# Copyright (C) 2013, 2014, 2019 Jaromir Hradilek <jhradilek@gmail.com>

# This program is  free software:  you can redistribute it and/or modify it
# under  the terms  of the  GNU General Public License  as published by the
# Free Software Foundation, version 3 of the License.
#
# This program  is  distributed  in the hope  that it will  be useful,  but
# WITHOUT  ANY WARRANTY;  without  even the implied  warranty of MERCHANTA-
# BILITY  or  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
# License for more details.
#
# You should have received a copy of the  GNU General Public License  along
# with this program. If not, see <http://www.gnu.org/licenses/>.

# -------------------------------------------------------------------------
#                            GLOBAL VARIABLES
# -------------------------------------------------------------------------

# General information about the script:
declare -r NAME=${0##*/}
declare -r VERSION='0.0.1'

# Counters for tested items:
declare -i ISSUES=0
declare -i CHECKED=0
declare -i FILES=0

# Command line options:
declare -i OPT_VERBOSITY=0
declare -i OPT_INCLUDES=0


# -------------------------------------------------------------------------
#       GENERIC FUNCTIONS REQUIRED FOR TESTING OF ASCIIDOC MODULES
# -------------------------------------------------------------------------

# Prints an error message to standard error output and terminates the
# script with a selected exit status.
#
# Usage: exit_with_error ERROR_MESSAGE [EXIT_STATUS]
function exit_with_error {
  local -r error_message=${1:-'An unexpected error has occurred.'}
  local -r exit_status=${2:-1}

  # Print the supplied message to standard error output:
  echo -e "$NAME: $error_message" >&2

  # Terminate the script with the selected exit status:
  exit $exit_status
}

# Prints a warning message to standard error output.
#
# Usage: warn WARNING_MESSAGE
function warn {
  local -r warning_message="$1"

  # Print the supplied message to standard error output:
  echo -e "$NAME: $warning_message" >&2
}

# Formats a test result message result and prints it to standard output.
#
# Usage: print_test_result STATUS EXPLANATION
function print_test_result {
  local -ru status="$1"
  local -r  explanation="$2"

  # Format the message and print it to standard output:
  printf "  %-9s %s\n" "[ $status ]" "$explanation"
}

# Records a test as passed and prints a related message to standard output.
#
# Usage: pass EXPLANATION
function pass {
  local -r explanation="$1"

  # Update the counter:
  (( CHECKED++ ))

  # Report a successfully passed test:
  [[ "$OPT_VERBOSITY" -gt 0 ]] && print_test_result " ok " "$explanation"
}

# Records a test as failed and prints a related message to standard output.
#
# Usage: fail EXPLANATION
function fail {
  local -r explanation="$1"

  # Update the counters:
  (( CHECKED++ ))
  (( ISSUES++ ))

  # Raport a failed test:
  print_test_result "fail" "$explanation"
}

# Deduces the documentat type from the file name and prints the result to
# standard output. If the document type cannot be determined, prints
# 'unknown'.
#
# Usage: detect_type FILE
function detect_type {
  local -r filename="${1##*/}"

  # Analyze the file name:
  case "$filename" in
    con_*) echo 'concept';;
    ref_*) echo 'reference';;
    proc_*) echo 'procedure';;
    assembly_*) echo 'assembly';;
    master.adoc) echo 'master';;
    local-attributes.adoc|attributes.adoc) echo 'attributes';;
    *) echo 'unknown';;
  esac
}

# Reads an AsciiDoc file, removes unwanted content such as comments from
# it, and prints the result to standard output.
#
# Usage: print_adoc FILE
function print_adoc {
  local -r filename="$1"

  # Remove both single-line and multi-line comments from the supplied file:
  perl -0pe 's{^////\s*\n.*?^////\s*\n}{}msg;s{^//.*\n}{}gm;' "$filename"
}

# Reads an AsciiDoc file and prints a list of all included files to
# standard output.
#
# Usage: print_includes FILE
function print_includes {
  local -r filename="$1"

  # Parse the AsciiDoc file, get a complete list of included files, and
  # print their full paths to standard output:
  ruby <<-EOF 2>/dev/null
#!/usr/bin/env ruby

require 'asciidoctor'
require 'pathname'

document = Asciidoctor.load_file("$filename", doctype: :book, safe: :safe)
document.reader.includes.each { |filename|
  path = Pathname.new("#{filename}.adoc")
  puts path.realpath
}
EOF

  # Verify that the AsciiDoc file could be processed and print a warning
  # if it could not:
  [[ "$?" -eq 0 ]] || warn "$filename: Unable to list included files"
}

# Processes the supplied AsciiDoc file and reports problems to standard
# output.
#
# Usage: print_report FILE
function print_report {
  local -r filename="$1"

  # Verify that the supplied file is an AsciiDoc file:
  [[ "${file##*.}" == 'adoc' ]] || exit_with_error "$file: Not an AsciiDoc file" 22

  # Verify that the supplied file exists and is readable:
  [[ -e "$file" ]] || exit_with_error "$file: No such file or directory" 2
  [[ -r "$file" ]] || exit_with_error "$file: Permission denied" 13
  [[ -f "$file" ]] || exit_with_error "$file: Not a file" 21

  # Determine the document type:
  local -r type=$(detect_type "$filename")

  # Get the full path for the tested file:
  local -r fullpath=$(realpath "$filename")

  # Print the header:
  echo -e "\nTesting file: $fullpath\n"
  echo -e "  Document type: $type\n"

  # Run test cases depending on the detected document type. If the document
  # type could not be determined, treat the file just like a module or
  # assembly:
  if [[ "$type" == 'attributes' ]]; then
    # Run test cases for attribute definition files:
    test_attributes_location "$filename"
    test_internal_definition "$filename"
    test_replaced_projects "$filename"
  elif [[ "$type" == 'master' ]]; then
    # Run test cases for master.adoc:
    test_context_definition "$filename"
    test_internal_definition "$filename"
    test_rhel_in_headings "$filename"
    test_replaced_projects "$filename"
    test_extarnal_links "$filename"
    test_old_rhel_links "$filename"
  else
    # Run test cases for modules and assemblies:
    test_internal_definition "$filename"
    test_module_prefix "$filename"
    test_steps_in_proc "$filename"
    test_steps_in_con "$filename"
    test_steps_in_ref "$filename"
    test_context_in_ids "$filename"
    test_rhel_in_headings "$filename"
    test_replaced_projects "$filename"
    test_extarnal_links "$filename"
    test_old_rhel_links "$filename"
    test_leveloffsets "$filename"
  fi

  # Update the counter:
  (( FILES++ ))
}

# Prints the summary of the test results to standard output.
#
# Usage: print_summary
function print_summary {
  # Print the summary:
  echo -e "\nChecked $CHECKED item(s) in $FILES file(s), found $ISSUES problem(s)."
}


# -------------------------------------------------------------------------
#                TEST CASES AND FUNCTIONS RELATED TO THEM
# -------------------------------------------------------------------------

# Parses the AsciiDoc file and prints all IDs to standard output.
#
# Usage: list_ids FILE
function list_ids {
  local -r filename="$1"

  # Parse IDs:
  print_adoc "$filename" | sed -ne "s/^\[id=['\"]\(.*\)['\"]\].*/\1/p"
}

# Parses the AsciiDoc file and prints all headings to standard output.
#
# Usage: list_headings FILE
function list_headings {
  local -r filename="$1"

  # Parse headings:
  print_adoc "$filename" | sed -ne "s/^=\+ \+\(.*\)$/\1/p"
}

# Parses the AsciiDoc file and prints all external links to standard
# output.
#
# Usage: list_links FILE
function list_links {
  local -r filename="$1"

  # Convert the AsciiDoc file to DocBook 4.5 and store the output in a
  # variable:
  local -r docbook=$(asciidoctor -S secure -b docbook45 -o - "$filename" 2>/dev/null)

  # Verify that the AsciiDoc file could be converted and print a warning
  # if it could not:
  if [[ "$?" -gt 0 ]]; then
    warn "$filename: Unable to convert to DocBook 4.5"
    return 1
  fi

  # Parse the DocBook 4.5 output and print all external links to standard
  # output:
  echo "$docbook" | \
    xmlstarlet sel -t -v '//ulink/@url' 2>/dev/null | \
    grep -e '^https\?://' | \
    sort -u | sed '/^$/d'
}

# Determines whether an external link is functional. If the target URL is
# not accessible, the function prints the broken link to standard output.
#
# Usage: print_broken URL
function print_broken {
  local -r url="$1"

  # Verify whether the supplied link is accessible:
  curl -A 'Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:65.0) Gecko/20100101 Firefox/65.0' \
       --connect-timeout 5 --retry 3 \
       -4ILfks "$url" &>/dev/null \
    || echo "$url"
}

# Parses the AsciiDoc file and determines whether it contains any steps.
#
# Usage: has_steps FILE
function has_steps {
  local -r filename=$1

  # Parse steps:
  print_adoc "$filename" | grep -qP '^\.+\s+\S+'
}

# Verifies that all attribute definitions are stored in the
# meta/attributes.adoc file to allow their reuse.
#
# Usage: test_attributes_location FILE
function test_attributes_location {
  local -r filename=$(realpath "$1")

  # Check if the file is located in meta/attribute.doc and report the
  # result:
  if [[ "$filename" == */meta/attributes.adoc ]]; then
    pass "Attribute definitions are stored in meta/attributes.adoc."
  else
    fail "Attribute definitions belong to meta/attributes.adoc to enable reuse."
  fi
}

# Verifies that the AsciiDoc file sets the value of the 'context' attribute
# to a non-empty string.
#
# Usage: test_context_definition FILE
function test_context_definition {
  local -r filename="$1"

  # Check if the file contains the attribute definition and report the
  # result:
  if print_adoc "$filename" | grep -qP '^:context:\s*\S+'; then
    pass "The 'context' attribute is set to a non-empty string."
  else
    fail "The 'context' attribute is not set to a non-empty string."
  fi
}

# Verifies that the AsciiDoc file does not define the 'internal' attribute.
#
# Usage: test_internal_definition FILE
function test_internal_definition {
  local -r filename="$1"

  # Check that the file does not contain the attribute definition and
  # report the result:
  if ! print_adoc "$filename" | grep -qP '^:internal:'; then
    pass "The 'internal' attribute is not defined."
  else
    fail "The 'internal' attribute is defined. Editorial comments are visible."
  fi
}

# Verifies that modules and assemblies follow prescribed naming conventions
# and use one of the following prefixes to signify their type:
#
#   con_      - a concept module
#   ref_      - a reference module
#   proc_     - a procedure module
#   assembly_ - an assembly
#
# Usage: test_module_prefix FILE
function test_module_prefix {
  local -r filename="$1"

  # Deduce the documentation type from the file name:
  local -r type=$(detect_type "$filename")

  # Check if the type could be deduced and report the result:
  if [[ "$type" != 'unknown' ]]; then
    pass "The file name uses the con_, ref_, proc_, or assembly prefix."
  else
    fail "The file name does not use the con_, ref_, proc_, or assembly_ prefix."
  fi
}

# Verifies that a procedure module contains at least one step.
#
# Usage: test_steps_in_proc FILE
function test_steps_in_proc {
  local -r filename="$1"

  # Determine the document type:
  local -r type=$(detect_type "$filename")

  # Check if the file is a procedure module and report the result,
  # otherwise do nothing:
  if [[ "$type" == 'procedure' ]]; then
    # Check if the file contains at least one step:
    if has_steps "$filename"; then
      pass "The procedure module contains at least one step."
    else
      fail "The procedure module does not contain any steps."
    fi
  fi
}

# Verifies that a concept module does not include any steps.
#
# Usage: test_steps_in_con FILE
function test_steps_in_con {
  local -r filename="$1"

  # Determine the document type:
  local -r type=$(detect_type "$filename")

  # Check if the file is a concept module and report the result,
  # otherwise do nothing:
  if [[ "$type" == 'concept' ]]; then
    # Check if the file contains at least one step:
    if ! has_steps "$filename"; then
      pass "The concept module does not contain any steps."
    else
      fail "The concept module contains one or more steps."
    fi
  fi
}

# Verifies that a reference module does not include any steps.
#
# Usage: test_steps_in_ref FILE
function test_steps_in_ref {
  local -r filename="$1"

  # Determine the document type:
  local -r type=$(detect_type "$filename")

  # Check if the file is a reference module and report the result,
  # otherwise do nothing:
  if [[ "$type" == 'reference' ]]; then
    # Check if the file contains at least one step:
    if ! has_steps "$filename"; then
      pass "The reference module does not contain any steps."
    else
      fail "The reference module contains one or more steps."
    fi
  fi
}

# Verifies that all IDs have the 'context' attribute in them to remain
# reusable in different assemblies.
#
# Usage: test_context_in_ids FILE
function test_context_in_ids {
  local -r filename="$1"

  # Locate all IDs used in the AsciiDoc file:
  while read unique_id; do
    # Check if the ID contains the 'context' attribute and report the
    # result:
    if echo "$unique_id" | grep -q '{context}'; then
      pass "The '$unique_id' ID includes the 'context' attribute."
    else
      fail "The '$unique_id' ID does not include the 'context' attribute."
    fi
  done < <(list_ids "$filename")
}

# Verifies that Red Hat Enterprise Linux is abbreviated in section headings
# for brevity.
#
# Usage: test_rhel_in_headings FILE
function test_rhel_in_headings {
  local -r filename="$1"

  # Locate all headings used in the AsciiDoc file:
  while read heading; do
    # Check that the heading does not spell out Red Hat Enterprise Linux
    # and report the result:
    if ! echo "$heading" | \
         grep -qP 'Red({nbsp}| )Hat({nbsp}| )Enterprise({nbsp}| )Linux|{RHEL}'; then
      # Check if the abbreviation is used to see if the success is worth
      # mentioning:
      if echo "$heading" | grep -qP '\bRHEL\b'; then
        pass "The heading '$heading' does not expand the RHEL abbreviation."
      fi
    else
      fail "The heading '$heading' does not use the RHEL abbreviation."
    fi
  done < <(list_headings "$filename")
}

# Verifies that none of the renamed or replaced projects are mentioned.
#
# Usage: test_replaced_projects FILE
function test_replaced_projects {
  local -r filename="$1"

  # Define a glossary of old and new project names:
  local -A projects
  projects['Cockpit']='RHEL web console'

  # Iterate over the project names:
  for name in "${!projects[@]}"; do
    # Check if the AsciiDoc file mentions the replaced project and report
    # the result:
    if ! print_adoc "$filename" | grep -qP "\b$name\b"; then
      pass "The '$name' project is not mentioned."
    else
      fail "The '$name' project is mentioned. Use ${projects[$name]} instead."
    fi
  done
}

# Verifies that all external links are functional.
#
# Usage: test_external_links FILE
function test_extarnal_links {
  local -r filename="$1"

  # Locate all external links used in the AsciiDoc file:
  local -r links=$(list_links "$filename")

  # Get a list of all broken links:
  export -f print_broken
  local -r broken=$(echo "$links" | xargs -n 1 -P 0 bash -c 'print_broken "$@"' --)

  # Report the results for broken links:
  while read link; do
    fail "Link is broken: '$link'"
  done < <(echo "$broken" | sed '/^$/d')

  # Report the results for functional links:
  while read link; do
    pass "Link is functional: '$link'"
  done < <(echo -e "$links\n$broken" | sed '/^$/d' | sort | uniq -u )
}

# Verifies that there are no links to older RHEL documentation, including
# a previous beta release.
#
# Usage: test_old_rhel_links FILE
function test_old_rhel_links {
  local -r filename="$1"

  # Locate all external links pointing to documentation for Red Hat
  # Enterprise Linux:
  local -r links=$(list_links "$filename" | grep -i '://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/')

  # Get a list of all links for older RHEL releases:
  local -r wrong=$(echo "$links" | grep -ie '://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/\([1-7]\|.-beta\)/')

  # Report the results for RHEL 7 links:
  while read link; do
    fail "Link refers to an older RHEL release: '$link'"
  done < <(echo "$wrong" | sed '/^$/d')

  # Report the results for non-problematic links:
  while read link; do
    pass "Link refers to the current RHEL release: '$link'"
  done < <(echo -e "$links\n$wrong" | sed '/^$/d' | sort | uniq -u )
}

# Verifies that only assemblies have includes, and that these always add
# exactly one level.
#
# Usage: test_leveloffsets FILE
function test_leveloffsets {
  local -r filename="$1"
  (print_adoc "$filename" | grep -qP "include::[^\[]+\[leveloffset=\+1\]")
  local -r good_leveloffsets="$?"
  (print_adoc "$filename" | grep -qP "include::[^\[]+\[(?!leveloffset=\+1)")
  local -r bad_leveloffsets="$?"
  (print_adoc "$filename" | grep -qP "include::[^\[]+\[")
  local -r any_includes="$?"
  # vars above:  zero if found, one if not found
  if [[ "$type" == 'assembly' ]] ; then
    if [[ "$any_includes" -gt 0 ]] ; then
      fail "Assembly does not contain any included modules."
    fi
  elif [ "$type" == 'procedure' ] || [ "$type" == 'concept' ] || [ "$type" == 'reference' ] ; then # tests all modules
    if [[ "$any_includes" -eq 0 ]] ; then
      fail "Module contains includes."
    fi
  fi
  if [[ "$bad_leveloffsets" -eq 0 ]]; then # test unclean leveloffsets in anything
    fail "Found leveloffsets that don't add exactly one level."
  fi
}


# -------------------------------------------------------------------------
#                               MAIN SCRIPT
# -------------------------------------------------------------------------

# Process command-line options:
while getopts ':hivV' OPTION; do
  case "$OPTION" in
    h)
      # Print usage information to standard output:
      echo "Usage: $NAME [-iv] FILE..."
      echo -e "       $NAME -hV\n"
      echo '  -i           also test included files'
      echo '  -v           include successful test results in the report'
      echo '  -h           display this help and exit'
      echo '  -V           display version and exit'

      # Terminate the script:
      exit 0
      ;;
    i)
      # Enable processing of included files:
      OPT_INCLUDES=1
      ;;
    v)
      # Increase the verbosity level:
      OPT_VERBOSITY=1
      ;;
    V)
      # Print version information to standard output:
      echo "$NAME $VERSION"

      # Terminate the script:
      exit 0
      ;;
    *)
      # Report invalid option and terminate the script:
      exit_with_error "Invalid option -- '$OPTARG'" 22
      ;;
  esac
done

# Shift positional parameters:
shift $(($OPTIND - 1))

# Verify the number of command line arguments:
[[ "$#" -gt 0 ]] || exit_with_error 'Invalid number of arguments' 22

# Verify that all required utilities are present in the system:
for dependency in asciidoctor curl xmlstarlet; do
  if ! type "$dependency" &>/dev/null; then
    exit_with_error "Missing dependency -- '$dependency'" 1
  fi
done

# Process the rest of the remaining command-line arguments:
for file in "$@"; do
  # Process the file and print the report:
  print_report "$file"

  # Check whether to also process included files:
  if [[ "$OPT_INCLUDES" -gt 0 ]]; then
    # Process each included file and print the report for it:
    while read include; do
      print_report "$include"
    done < <(print_includes "$file")
  fi
done

# Print the summary:
print_summary

# Terminate the script:
[[ "$ISSUES" -eq 0 ]] && exit 0 || exit 1
