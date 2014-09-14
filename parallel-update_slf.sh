#!/bin/sh

##### Default settings #########################################################
# Path to GNU Parallel
PARALLEL=parallel

SLEEP="10s"
TIMEOUT="1000%"

##### Usage ####################################################################
usage() {
   SCRIPT="$(basename $0)"
   echo
   echo "GNU Parallel wrapper for dynamically filtering out unaccessible remote hosts"
   echo ""
   echo "Usage: $SCRIPT --slf <file> [--sleep <n>] [--timeout <n[%]>] -- "
   echo "          [... GNU Parallel's command options ...]"
   echo
   echo "where:"
   echo
   echo "  --slf <file>, --sshloginfile <file>"
   echo "     GNU Parallel's ssh login file (\".\" and \"..\" are also valid)"
   echo "  --sleep <n>"
   echo "     Idle time between checking hosts' availability (default = 10s)"
   echo "  --timeout <n[%]>"
   echo "     Time out for hosts' response (if followed by a % then the timeout"
   echo "     will be based on the median average response time)"
   echo
   echo "Example:"
   echo "   seq 1 50 | $SCRIPT --slf hosts.slf -- 'sleep {}; echo \$(hostname) ran sleep for {}s'"
   echo ""

   echo "This is free software. You may redistribute copies of it under the terms"
   echo "of the GNU General Public License <http://www.gnu.org/licenses/gpl.html>."
   echo "There is NO WARRANTY, to the extent permitted by law."
   echo ""
   echo "Written by Douglas A. Augusto (daaugusto)."

   exit $1
}

##### update_daemon ############################################################
update_daemon() {
   cp "${SLF}" "${UPDATED_SLF}"

   while [ 1 ] ; do
      nice "${PARALLEL}" --timeout "${TIMEOUT}" --nonall -j0 -k --slf "${SLF}" --tag echo | \
         sed -e 's#\t$##' -e '#\t#d' | \
         nice ${PARALLEL} -k perl -ne \"\\\$host=\'{}\'";\\\$host=~s#\\\\\##g;/^(\d+\/)?\\\\Q\\\$host\\\\E\\\$/ and print and exit"\" "${SLF}" > "${TMP_SLF}"
      if ! cmp -s "${TMP_SLF}" "${UPDATED_SLF}"; then
         mv "${TMP_SLF}" "${UPDATED_SLF}"
      fi

      sleep ${SLEEP}
   done
}

##### Clean up function ########################################################
finish() {
   # Clear traps to avoid calling this function twice
   trap - EXIT INT
   # Remove temporary files
   rm -f -- "${TMP_SLF}" "${UPDATED_SLF}"
   # Kill daemon
   kill $DAEMON_PID >/dev/null 2>&1
}

##### Parsing and initialization ###############################################
# Check if GNU Parallel is reachable
if ! type ${PARALLEL} > /dev/null 2>&1; then { echo "> Error: GNU Parallel has not been found [${PARALLEL}]."; exit 2; }; fi

# Parse options
COUNT=0
while [ $# -ge 1 ]; do
   case "$1" in
      "--slf"|"--sshloginfile")
         shift;
         case "$1" in
            ".")  SLF="$HOME/.parallel/sshloginfile";;
            "..") SLF="/etc/parallel/sshloginfile";;
            *)    SLF="$1";;
         esac
         shift;;
      "--sleep") shift; SLEEP="$1"; shift;;
      "--timeout") shift; TIMEOUT="$1"; shift;;
      "-h"|"--help") usage 0;;
      "--") shift; break;;
      *) break;;
   esac
   # No need to parse past the number of defined options
   COUNT=$((COUNT+1)); [ $COUNT -ge 5 ] && break;
done

# Check options
[ -e "${SLF}" ] || { echo "> Error: ssh login file not found [${SLF}]."; usage 1; }

# Clean up after normal exit (EXIT) or after the user presses Ctrl-C (INT)
trap finish EXIT INT

# Temporary files
TMP_SLF="$(mktemp --tmpdir $$T-XXXXX.slf)"
UPDATED_SLF="$(mktemp --tmpdir $$U-XXXXX.slf)"

##### Start the daemon to filter out unaccessible servers ######################
update_daemon "${SLF}" &
DAEMON_PID=$!

##### Run GNU Parallel with user provided options ##############################
${PARALLEL} --slf "${UPDATED_SLF}" "$@"
