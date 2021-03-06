#!/bin/sh
set -e

readonly SOURCE_FILE=$1
[ -z "$SOURCE_FILE" ] && { printf 'Source file required.\n'; exit 1; }
[ \! -f "$SOURCE_FILE" ] && { printf 'Source file does not exist or is not a regular file.\n'; exit 1; }

PATH=.:$PATH . DSshell.sh

app           () { dsh_elem app                        "$@"; }

sensor        () { dsh_elem app/sensor                 "$@"; }
actuator      () { dsh_elem app/actuator               "$@"; }
state         () { dsh_elem app/state                  "$@"; }
initial_state () { dsh_elem app/initial_state          "$@"; }
		   
pin           () {
    if ! dsh_elem app/sensor/pin "$@"
    then
	dsh_debug_info 'Could not define ping under app/sensor. Trying under app/actuator.\n'
	dsh_elem app/actuator/pin "$@"
    fi
}
change        () { dsh_elem app/state/change           "$@"; }
when          () { dsh_elem app/state/when             "$@"; }

to            () { dsh_elem app/state/change/to        "$@"; }
has_value     () { dsh_elem app/state/when/has_value   "$@"; }
go_to_state   () { dsh_elem app/state/when/go_to_state "$@"; }



## This is where we import the source file. By calling the method that
## we just defined, this file will create an AST that we will be able
## to query using the dsh_* helpers.
. "$SOURCE_FILE"



indent () {
    sed 's|^|'"$(printf "%$1s" '')"'|'
}

print_app () {
    local app=$1; shift

    printf '// This file has been generated by ArduinoML.sh\n'
    
    printf '\nlong time = 0;\nlong debounce = 200;\n'
    
    print_variables "$app"
    
    printf '\nvoid setup () {\n'
    print_setup "$app" | indent 2
    printf '}\n'

    dsh_get_descendants_of_type "$app" app/state | \
	while read state
	do
	    printf '\nvoid state_%s () {\n' "$(dsh_get_value_from_path "$state")"
	    print_state "$state" | indent 2
	    printf '}\n'
	done
    
    printf '\nvoid loop () {\n'
    print_loop "$app" | indent 2
    printf '}\n'
}

print_variables () {
    local app=$1; shift
    local pin=
    local sensor_value=
    local actuator_value=
    local pin_value=
    
    ## foreach pin of type app/sensor/pin in this $app
    dsh_get_descendants_of_type "$app" app/sensor/pin | \
	while read pin
	do
	    sensor_value=$(dsh_get_prefix_value_from_type "$pin" app/sensor)
	    pin_value=$(dsh_get_value_from_path "$pin")
	    
	    printf 'int sensor_%s = %d;\n' "$sensor_value" "$pin_value"
	done
    
    ## foreach pin of type app/actuator/pin in this $app
    dsh_get_descendants_of_type "$app" app/actuator/pin | \
	while read pin
	do
	    actuator_value=$(dsh_get_prefix_value_from_type "$pin" app/actuator)
	    pin_value=$(dsh_get_value_from_path "$pin")
	    
	    printf 'int actuator_%s = %d;\n' "$actuator_value" "$pin_value"
	done
}

print_setup () {
    local app=$1; shift
    local pin=
    local sensor_value=
    local actuator_value=

    ## foreach pin of type app/sensor/pin in this $app
    dsh_get_descendants_of_type "$app" app/sensor/pin | \
	while read pin
	do
	    sensor_value=$(dsh_get_prefix_value_from_type "$pin" app/sensor)

	    printf 'pinMode(sensor_%s, INPUT);\n' "$sensor_value";
	done

    ## foreach pin of type app/actuator/pin in this $app
    dsh_get_descendants_of_type "$app" app/actuator/pin | \
	while read pin
	do
	    actuator_value=$(dsh_get_prefix_value_from_type "$pin" app/actuator)
	    
	    printf 'pinMode(sensor_%s, OUTPUT);\n' "$actuator_value"
	done
}

print_state () {
    local state=$1; shift

    ## foreach 'to' of type app/state/change/to in this $state
    dsh_get_descendants_of_type "$state" app/state/change/to | \
	while read to
	do
	    print_changeto "$to"
	done
    
    ## foreach 'when' of type app/state/when in this $state
    dsh_get_children_of_type "$state" app/state/when | \
	while read when
	do
	    print_when "$when"
	done

    printf 'state_%s();\n' "$(dsh_get_value_from_path "$state")"
}

print_changeto () {
    local to=$1; shift
    local to_value=$(dsh_get_value_from_path "$to")
    local change_value=$(dsh_get_prefix_value_from_type "$to" app/state/change)			
    
    printf 'digitalWrite(actuator_%s, %s);\n' "$change_value" "$to_value"
}

print_when () {
    local when=$1; shift
    local when_value=$(dsh_get_value_from_path "$when")
    local hasvalue_value=$(dsh_get_value_from_path "$(dsh_get_child_of_type "$when" app/state/when/has_value)")
    local gotostate_value=$(dsh_get_value_from_path "$(dsh_get_child_of_type "$when" app/state/when/go_to_state)")

    ## FIXME: one time/debounce per sensor?
    
    printf 'if ((digitalRead(sensor_%s) == %s) && (millis() - time > debounce)) {\n' "$when_value" "$hasvalue_value"
    printf '  time = millis();\n'
    printf '  state_%s();\n' "$gotostate_value"
    printf '  return;\n'
    printf '}\n'
}

print_loop () {
    local app=$1; shift
    local initialstate_value=$(dsh_get_value_from_path "$(dsh_get_child_of_type "$app" app/initial_state)")
    printf 'state_%s();\n' "$initialstate_value"
}

## foreach app of type app everywhere
dsh_get_children_of_type '' app | \
    while read app
    do
	print_app "$app"
    done

dsh_cleanup
