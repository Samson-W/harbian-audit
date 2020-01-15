#!/bin/bash

#
# harbian audit debian 9 or CentOS8 Hardening
#

#
# 10.1.8 Set FAIL_DELAY Parameters Using pam_faildelay (Scored)
# Author : Samson wen, Samson <sccxboy@gmail.com>
#

set -e # One error, it's over
set -u # One variable unset, it's over

HARDENING_LEVEL=2

audit_debian () {
    is_pkg_installed $PACKAGE
    if [ $FNRET != 0 ]; then
        crit "$PACKAGE is not installed!"
        FNRET=1
    else
        ok "$PACKAGE is installed"
        does_pattern_exist_in_file $FILE $PATTERN
        if [ $FNRET = 0 ]; then
            ok "$PATTERN is present in $FILE"
            check_param_pair_by_pam $FILE $PAMLIBNAME $OPTIONNAME ge $CONDT_VAL  
            if [ $FNRET = 0 ]; then
                ok "$OPTIONNAME set condition is $CONDT_VAL"
            else
                crit "$OPTIONNAME set condition is not equal or greater than $CONDT_VAL"
            fi
        else
            crit "$PATTERN is not present in $FILE"
            FNRET=2
        fi
    fi
}

audit_redhat () {
	for SSH_OPTION in $OPTIONS; do
		SSH_PARAM=$(echo $SSH_OPTION | cut -d= -f 1)
		SSH_VALUE=$(echo $SSH_OPTION | cut -d= -f 2)
		PATTERN="^$SSH_PARAM[[:space:]]*$SSH_VALUE"
		does_pattern_exist_in_file $FILE "$PATTERN"
		if [ $FNRET = 0 ]; then
			ok "$PATTERN is present in $FILE"
		else
			crit "$PATTERN is not present in $FILE"
		fi
	done
}

# This function will be called if the script status is on enabled / audit mode
audit () {
	if [ $OS_RELEASE -eq 2 ]; then
		audit_redhat
	else
		audit_debian
	fi
}

apply_debian () {
    if [ $FNRET = 0 ]; then
        ok "$PACKAGE is installed"
    elif [ $FNRET = 1 ]; then
        crit "$PACKAGE is absent, installing it"
        install_package $PACKAGE
    elif [ $FNRET = 2 ]; then
        crit "$PATTERN is not present in $FILE, add default config to $FILE"
        add_line_file_before_pattern $FILE "auth       optional   pam_faildelay.so  delay=4000000" "# Outputs an issue file prior to each login prompt (Replaces the"
    elif [ $FNRET = 3 ]; then
        crit "$FILE is not exist, please check"
    elif [ $FNRET = 4 ]; then
        crit "$OPTIONNAME is not conf"
        add_option_to_auth_check $FILE $PAMLIBNAME "$OPTIONNAME=$CONDT_VAL"
     elif [ $FNRET = 5 ]; then
        crit "$OPTIONNAME set is not match legally, reset it to $CONDT_VAL"
        reset_option_to_auth_check $FILE $PAMLIBNAME "$OPTIONNAME" "$CONDT_VAL"
    fi 
}

apply_redhat () {
	for SSH_OPTION in $OPTIONS; do
		SSH_PARAM=$(echo $SSH_OPTION | cut -d= -f 1)
		SSH_VALUE=$(echo $SSH_OPTION | cut -d= -f 2)
		PATTERN="^$SSH_PARAM[[:space:]]*$SSH_VALUE"
		does_pattern_exist_in_file $FILE "$PATTERN"
		if [ $FNRET = 0 ]; then
			ok "$PATTERN is present in $FILE"
		else
			warn "$PATTERN is not present in $FILE, adding it"
			does_pattern_exist_in_file $FILE "^$SSH_PARAM"
			if [ $FNRET != 0 ]; then
				add_end_of_file $FILE "$SSH_PARAM $SSH_VALUE"
			else
				info "Parameter $SSH_PARAM is present but with the wrong value -- Fixing"
				replace_in_file $FILE "^$SSH_PARAM[[:space:]]*.*" "$SSH_PARAM $SSH_VALUE"
			fi
		fi
	done
}

# This function will be called if the script status is on enabled mode
apply () {
	if [ $OS_RELEASE -eq 2 ]; then
		apply_redhat
	else
		apply_debian
	fi
}

# This function will check config parameters required
check_config() {
	# CentOS
	if [ $OS_RELEASE -eq 2 ]; then
		OPTIONS='FAIL_DELAY=4'
		FILE='/etc/login.defs'
	# Debian
	else
		PACKAGE='libpam-modules'
		PAMLIBNAME='pam_faildelay.so'
		PATTERN='^auth.*pam_faildelay.so'
		FILE='/etc/pam.d/login'
		OPTIONNAME='delay'
		# condition (microseconds)
		CONDT_VAL=4000000
	fi
}

# Source Root Dir Parameter
if [ -r /etc/default/cis-hardening ]; then
    . /etc/default/cis-hardening
fi
if [ -z "$CIS_ROOT_DIR" ]; then
     echo "There is no /etc/default/cis-hardening file nor cis-hardening directory in current environment."
     echo "Cannot source CIS_ROOT_DIR variable, aborting."
    exit 128
fi

# Main function, will call the proper functions given the configuration (audit, enabled, disabled)
if [ -r $CIS_ROOT_DIR/lib/main.sh ]; then
    . $CIS_ROOT_DIR/lib/main.sh
else
    echo "Cannot find main.sh, have you correctly defined your root directory? Current value is $CIS_ROOT_DIR in /etc/default/cis-hardening"
    exit 128
fi
