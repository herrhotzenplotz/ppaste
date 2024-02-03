#!/bin/sh

# Written by: panku
# Thanks to: o1, deesix, genunix

# Source code is hosted on : "https://www.github.com/pankunull/ppaste"
# Pastebin is hosted on    : "https://www.oetec.com/pastebin"

# POSIX



###############################################################
# Variables
###############################################################

version="0.5.13"

script_name="$(basename "$0")"
script_dir="$(dirname "$0")"
script_hash="$(sha256sum "$script_dir/$script_name" | cut -d ' ' -f1)"

github_source='https://raw.githubusercontent.com/pankunull/ppaste/main/src/ppaste.sh'
github_hash='https://raw.githubusercontent.com/pankunull/ppaste/main/sign/sha256sum.txt'

pastebin=https://www.oetec.com/pastebin

pwcmd='curl --silent --connect-timeout 5 --location'

history_file=~/"$script_name"/history
history_file_table=~/"$script_name"/history_table

download_dir=~/"$script_name"/download

save_session=0
lifetime=0
format=none
file_flag=0

file_max_size=300000000

width=13
help_width=30



###############################################################
# Exit code
###############################################################

error()
{
    printf "error: %s\n" "$1"

    case "$2" in
        0) exit 0 ;;
        1) exit 1 ;;
    esac
}



error_no_arg()
{
    printf "error: missing argument\n\n"

    exit 1
}


###############################################################
# Options
###############################################################

save_session()
{
    if [ ! -f "$history_file" ]; then
        if mkdir -p ~/"$script_name" && touch "$history_file"; then
            printf "History file created: %s\n\n" "$history_file"
        else
            error "failed to create history file" 1
        fi
    fi 
    
    save_session=1

}



expire_time()
{   
    case "$1" in
        ''|*[!0-7]*)
            error "expire value has to be between 0 and 7" 1 
            ;;
        *) lifetime="$1" ;;
    esac
}



###############################################################
# Output
###############################################################
output_format()
{
    case "$1" in
          all) format='all'    ;;
       editor) format='editor' ;;
        plain) format='plain'  ;;
        lined) format='lined'  ;;
            *)
                error "format not valid" 
                usage
                ;;
    esac
}



###############################################################
# History
###############################################################

show_history()
{
    if [ ! -f "$history_file" ]; then
        error "history file doesn't exist" 1
    elif [ -z "$history_file" ]; then
        error "history is empty" 1
    fi 
        
    printf "Grabbing history from '%s'\n\n" "$history_file"
        
    case "$1" in
        alive) history_links="$(awk -F\, '$3 < '"$(date +%s)"'' "$history_file")" ;;
         dead) history_links="$(awk -F\, '$3 > '"$(date +%s)"'' "$history_file")" ;;
          all) history_links="$(cat "$history_file")" ;;
        *)
            error "bad argument"
            usage
        ;;
    esac

    history_links="$(echo "$history_links" | cut -d '|' -f1)"

    if [ -n "$history_links" ]; then
        printf "%s\n" "$history_links"
    else
        printf "%s\n" "No results"
        exit 0
    fi

    exit 0
}



show_history_table()
{
    if ! [ -f "$history_file" ]; then
        error "history file doesn't exist" 1
    elif [ -z "$history_file" ]; then
        error "history is empty" 1
    fi 

    printf "Grabbing history from '%s'\n\n" "$history_file"

    case "$1" in
        alive) history_links="$(awk -F\, '$3 < '"$(date +%s)"'' "$history_file")" ;;
         dead) history_links="$(awk -F\, '$3 > '"$(date +%s)"'' "$history_file")" ;;
          all) history_links="$(cat "$history_file")" ;;
        *)
            error "bad argument"
            usage
        ;;
    esac

    if [ -z "$history_links" ]; then
        printf "%s\n" "No results"
        exit 0
    fi

    minus=128

    # Table's header
    {
        printf -- "-%.0s" $(seq 1 "$minus")
        printf "\n"
        printf "%22s %17s %18s %9s %18s %9s %s %s %s\n" \
               "Link" "|" "Created on" "|" "Expires on" "|" "Lifetime" "|" "Filename"
        printf -- "-%.0s" $(seq 1 "$minus")
        printf "\n"
    } > "$history_file_table"

    awk 'BEGIN {FS=OFS="|";}
               {$2 = strftime("%c %Z", $2); $3 = strftime("%c %Z", $3); } 
               {print}' "$history_file" | \
    awk -F '|' '{ if ($4 == "1")    $4="1 day     "  }1' OFS='|' | \
    awk -F '|' '{ if (int($4) > 1 ) $4=$4" days    " }1' OFS='|' | \
    awk -F '|' '{ if ($4 == "0")    $4="4 hours   "  }1' OFS='|' >> "$history_file_table"

    sed -i -e 's/|/ | /g' "$history_file_table"

    printf -- "-%.0s" $(seq 1 "$minus") >> "$history_file_table"
    printf "\n" >> "$history_file_table"

    cat "$history_file_table"

    printf "\n"

    exit 0
}



delete_history()
{
    if ! [ -f "$history_file" ]; then
        error "history file doesn't exist" 1
    fi 

    printf "Are you sure you want to delete the history? [y/N]: "

    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting\n"
            exit 0
            ;;
    esac

    rm -v "$history_file"

    exit 0

}


###############################################################
# Download
###############################################################


download()
{
    if [ ! -d "$download_dir" ]; then
        printf "Creating download folder: %s\n\n" "$download_dir"
    
        if ! mkdir -p "$download_dir"; then
            error "can't create the download folder" 1
        fi
    fi


    for link in $1; do
        ### Check if the link is valid using grep
        ### If the header contains the expiration date it's a valid link
        if echo "$link" | grep -q "$pastebin"; then
            download_hash="$(echo "$link" | cut -d '|' -f1 | rev | cut -d '/' -f1 | rev)"
            download_link="$pastebin"/plain/"$download_hash"

        elif [ "${#link}" = '8' ]; then
            download_hash="$link"
            download_link="$pastebin"/plain/"$link"

        else
            error "not a valid link or hash" 1
        fi
        

        if ! headers="$($pwcmd -I --url "$download_link")"; then
            error  "curl error" 1
        fi
            
        if ! echo "$headers" | grep --silent -q -v 'Expires'; then
            error "paste not found on the server" 1
        fi

        download_name="$(echo "$headers" | grep filename | cut -d '=' -f2 | tr -d '"\r')"

        if [ ! -f "$download_dir"/"$download_name" ]; then
            printf "%${width}s : %s\n" "Downloading" "$download_name"

            COLUMNS=63 curl --progress-bar -# -4 -L \
                            --url "$download_link" \
                            -o "$download_name" \
                            --output-dir "$download_dir"

            printf "\n"
        else
            printf "File %s already exist\n\n" "$download_name"
        fi
    done

    printf "Done: %s\n" "$download_dir"

    exit 0
}



download_alive()
{

    if ! [ -f "$history_file" ]; then
        error "history file doesn't exist" 1
    fi 

    printf "Grabbing history from '%s'\n\n" "$history_file"

    history_download="$(awk -F\, '$2 < '"$(date +%s)"'' "$history_file")"

    if [ -z "$history_download" ]; then
        printf "No history found\n\n"
        exit 0
    fi
    
    if [ ! -d "$download_dir" ]; then
        printf "Creating download folder in %s\n\n" "$download_dir"
    
        if ! mkdir -p "$download_dir" 2>&1; then
            error "can't create the download folder" 1
        fi
    
    fi

    printf "If the file is already in the folder it won't be downloaded.\n\n"
    printf "There are %s entries in the history, continue? [y/N]: " "$(wc -l "$history_file" | cut -d ' ' -f1)"

    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting\n"
            exit 0
            ;;
    esac

    printf "\n"

    for link in $history_download; do
        download_hash="$(echo "$link" | cut -d '|' -f1 | rev | cut -d '/' -f1 | rev)"
        download_name="$(echo "$link" | rev | cut -d '|' -f1 | rev)"
        link="$pastebin/plain/$download_hash"

        if [ ! -f "$download_dir"/"$download_name" ]; then
            printf "%${width}s : %s\n" "Downloading" "$download_name"

            COLUMNS=63 curl --progress-bar -# -4 -L \
                            --url "$download_link" \
                            -o "$download_name" \
                            --output-dir "$download_dir"

            printf "\n"
        fi
    done

    printf "Done: %s\n\n" "$download_dir"

    exit 0
}



delete_download()
{
    if ! [ -f "$history_file" ]; then
        error "history file doesn't exist" 1
    fi 

    printf "Are you sure you want to delete the download folder? [y/N]: "

    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting\n"
            exit 0
            ;;
    esac

    rm -v -r "$download_dir"

    exit 0
}



###############################################################
# Utilities
###############################################################

check_link()
{
    link="$1"

    ### Check if the link is valid using grep
    ### If the header contains the expiration date it's a valid link
    if echo "$link" | grep -q "$pastebin"; then
        download_hash="$(echo "$link" | cut -d '|' -f1 | rev | cut -d '/' -f1 | rev)"
        download_link="$pastebin"/plain/"$download_hash"

    elif [ "${#link}" = '8' ]; then
        download_hash="$link"
        download_link="$pastebin"/plain/"$link"

    else
        error "not a valid link or hash" 1
    fi
    

    if ! headers="$($pwcmd -I --url "$download_link")"; then
        error  "curl error" 1
    fi
        
    if ! echo "$headers" | grep 'Expires'; then
        error "paste not found on the server" 1
    fi

    #download_name="$(echo "$headers" | grep filename | cut -d '=' -f2 | tr -d '"\r')"

    server_hash="$(echo "$link" | rev | cut -d '/' -f1 | rev)"
    server_type="$(echo "$headers" | grep "Type: " | cut -d ' ' -f2-)"

    headers="$(echo "$headers" | tr -d '\r')"

    server_create_date="$(echo "$headers" | grep "Date: " | cut -d ' ' -f2-)"
    server_expire_date="$(echo "$headers" | grep "Expires: " | cut -d ' ' -f2-)"

    server_epoch_create="$(date --date "$server_create_date" +%s 2>/dev/null || \
                           date -j -f '%a%d%b%Y%H%M%S%Z' "$(echo "$server_create_date" | tr -d ' ,:')" +%s)"

    server_epoch_expire="$(date --date "$server_expire_date" +%s 2>/dev/null || \
                           date -j -f '%a%d%b%Y%H%M%S%Z' "$(echo "$server_expire_date" | tr -d ' ,:')" +%s)"

    local_create_date="$(date --date @"$server_epoch_create" 2>/dev/null || \
                         date -r "$server_epoch_expire")"
    local_expire_date="$(date --date @"$server_epoch_expire" 2>/dev/null || \
                         date -r "$server_epoch_expire")"


    offset=$(( server_epoch_expire - server_epoch_create ))

    printf "%${width}s : %s\n" "Created on" "$local_create_date"
    printf "%${width}s : %s\n" "Epires on" "$local_expire_date"
    printf "%${width}s : %s\n" "Hash" "$server_hash"
    printf "%${width}s : %s\n" "Type" "$server_type"

    printf "%${width}s : %sd %sh %sm %ss\n\n" \
        "Lifetime" \
        "$((  offset / 86400))" \
        "$(( (offset % 86400) / 3600))" \
        "$(( (offset % 3600) / 60))" \
        "$((  offset % 60))"

    exit 0
}




###############################################################
# Misc
###############################################################

upgrade()
{
    ### Check if source is reachable
    if ! server_version="$($pwcmd --url "$github_source")"; then
        error "curl failed" 1
    fi


    ### Grab version
    server_version="$(echo "$server_version" |\
                      grep -m 1 "version" |\
                      cut -d '=' -f2 |\
                      tr -d '"')"


    ### Check if the new version has been grabbed
    if [ -z "$server_version" ]; then
        error "can't fetch version" 1
    fi
    

    server_hash="$($pwcmd --url $github_hash | cut -d ' ' -f1)"


    printf "Local version  : %s\n%s\n\n" "$version" "$script_hash"
    printf "Latest version : %s\n%s\n\n" "$server_version" "$server_hash"


    ### Check version
    if [ "$(echo "$version" | tr -d '.')" = \
         "$(echo "$server_version" | tr -d '.')" ]; then
        printf "Up-to-date\n\n"

        if [ "$server_hash" != "$script_hash" ]; then
            printf "WARNING: version is up-to-date but the hash doesn't match.\n"
            printf "\t You are using a modified version of the script.\n\n"
        fi

        exit 0
    fi


    printf "Do you want to upgrade? [y/N]: "
    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting\n"
            exit 0
            ;;
    esac


    ## Upgrade
    if ! $pwcmd --url "$github_source" \
                 --output /tmp/"$script_name".new; then
        error "curl failed"
    fi

    printf "\nFile downloaded to: %s\n" "$(ls /tmp/"$script_name".new)"

    printf "Do you want to overwrite the current script? [y/N]: "

    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting"
            exit 0
            ;;
    esac

    mv -v "$0" "$0".old
    mv -v /tmp/"$script_name".new "$script_dir/$script_name"
    chmod -v +x "$script_dir/$script_name"
    rm -v "$0".old

    printf "\nDone!\n\n"

    exit 0
}



force_upgrade()
{
    ### Check if source is reachable
    if ! server_version="$($pwcmd --url "$github_source")"; then
        error "curl failed" 1
    fi


    printf "Do you want to upgrade? [y/N]: "
    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting\n"
            exit 0
            ;;
    esac


    ### Upgrade
    if ! $pwcmd --url "$github_source" \
                 --output /tmp/"$script_name".new; then
        error "curl failed"
    fi

    printf "\nFile downloaded to: %s\n" "$(ls /tmp/"$script_name".new)"

    printf "Do you want to overwrite the current script? [y/N]: "

    read -r choice

    case "$choice" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            printf "Aborting"
            exit 0
            ;;
    esac


    mv -v "$0" "$0".old
    mv -v /tmp/"$script_name".new "$script_dir/$script_name"
    chmod -v +x "$script_dir/$script_name"
    rm -v "$0".old
    
    printf "\nDone!\n\n"

    exit 0
}



help_page()
{
    printf "Usage: %s [OPTIONS] <file1> <file...>\n\n" "$script_name"
    
    printf "Options:\n"
    #printf " %-${help_width}s Files to paste\n" "-f, --files"
    printf " %-${help_width}s Expire time (w/given is 4 hours)\n" "-e, --expire-time NUM"
    printf " %-${help_width}s NUM is '0' for 4 hours and '1-7' for days\n" " "
    printf " %-${help_width}s Save session in history\n" "-s, --save-session"

    printf "\nOutput:\n"
    printf " %-${help_width}s Print links at the end of the session\n" "-o, --output-format FORMAT"
    printf " %-${help_width}s FORMAT is 'all', 'editor', 'plain', 'lined'\n" " "
    
    printf "\nHistory:\n"
    printf " %-${help_width}s Show normal history (links)\n" "-l, --history FORMAT"
    printf " %-${help_width}s Show formatted history (table)\n" "-L, --history-table FORMAT"
    printf " %-${help_width}s FORMAT is 'alive', 'dead', 'all'\n" " "
    printf " %-${help_width}s Delete history\n" "-r, --delete-history"

    printf "\nDownload:\n"
    printf " %-${help_width}s Download file using url or hash\n" "-d, --download <url>[,<hash]"
    printf " %-${help_width}s Download alive links\n" "-D, --download-alive"
    printf " %-${help_width}s Delete download folder\n" "-R, --delete-download"

    printf "\nUtilities:\n"
    printf " %-${help_width}s Check expiration date via url or hash\n" "-c, --check <url>[,<hash>]"

    printf "\nMisc:\n"
    printf " %-${help_width}s Upgrade\n" "-u, --upgrade"
    printf " %-${help_width}s Force upgrade\n" "-U, --force-upgrade"
    printf " %-${help_width}s Help page\n" "-h, --help"
    printf " %-${help_width}s Version\n" "-v, --version"


    printf "\nExamples:\n"
    printf " %s file1.txt file2.txt\n" "$script_name"
    printf " %s --save-session -e 1 file1.txt file2.txt\n" "$script_name"
    printf " %s file1.txt -e 1 -s file2.txt\n" "$script_name"
    printf "\n"

    exit 0
}


version()
{
    printf "Version: %s\n" "$version"
    printf "%s\n\n" "$script_hash"

    exit 0
}



###############################################################
# File upload
###############################################################

file_upload()
{
    file="$1"

    ### Payload check
    if ! [ -f "$file" ]; then
        error "file doesn't exist"
        return
    elif ! [ -r "$file" ]; then
        error "file '$file' is not readable"
        return
    elif ! [ -s "$file" ]; then
        error "file '$file' is empty"
        return
    elif [ ! "$(wc -c < "$file")" -lt "$file_max_size" ]; then
        error "file '$file' exceeds size limit ($((file_max_size / 1000000)) MB)"
        return
    else
        file_to_upload="pastefile=@$file"
    fi 


    ### Initializing
    printf "Sending: %s\n" "$file"
    

    ### Liftoff
    payload="$(COLUMNS=63 \
                curl --progress-bar --output - -# \
                --connect-timeout 5 \
                --form post=pastebin \
                --form days="$lifetime" \
                --form "$file_to_upload" \
                https://www.oetec.com/post 2>/dev/null)"
 

    ### Error code 
    if [ "$?" -gt 0 ]; then
        error "curl failed" 1
    fi

    ### 404
    if echo "$payload" | grep "404" 1>/dev/null; then
        error "404 - page not found" 1
    fi


    ### POST error
    if echo "$payload" | grep -i "fail" 1>/dev/null; then
        error "POST failed, check forms" 1
    fi


    ### Payload's informations
    ### Time
    epoch_create_time="$(date '+%s')"
    date_create_time="$(date --date @"$epoch_create_time" 2>/dev/null || \
                        date -r "$epoch_create_time")"
    

    ### Create epoch and date
    #### Calculating the time using an offset it's easier for POSIX compatibility
    if [ "$lifetime" -eq 0 ]; then
        epoch_expire_offset="$(( epoch_create_time + 14000 ))"
        date_expire_time="$(date --date @"$epoch_expire_offset" 2>/dev/null || \
                            date -r "$epoch_expire_offset")"
    else
        epoch_expire_offset="$(( lifetime * 86400 ))"
        epoch_expire_time="$(( epoch_create_time + epoch_expire_offset ))"
        date_expire_time="$(date --date @"$epoch_expire_time" 2>/dev/null || \
                            date -r "$epoch_expire_time")"
    fi

    case "$lifetime" in
            0) date_time_offset="4 hours" ;;
            1) date_time_offset="$lifetime day" ;;
        [2-7]) date_time_offset="$lifetime days" ;;
    esac


    ### Print date/time informations
    printf "%${width}s : %s\n" "Created on" "$date_create_time"
    printf "%${width}s : %s\n" "Expires on" "$date_expire_time"
    printf "%${width}s : %s\n" "Lifetime" "$date_time_offset"


    #### Hash
    file_hash="$(echo "$payload" | sed '1p;d' | rev | cut -d '/' -f1 | rev)"
    printf "%${width}s : %s\n" "Hash" "$file_hash"


    ### Links list
    link_editor="$(echo "$payload" | sed '1p;d')"
    link_lined="$(echo "$payload" | sed '2p;d')"
    link_plain="$(echo "$payload" | sed '3p;d')"


    ### Session save
    if [ "$save_session" -eq 1 ]; then
        {
            printf "%s|" "$link_editor"
            printf "%s|" "$epoch_create_time"
            printf "%s|" "$epoch_expire_time"
            printf "%s|" "$lifetime"
            printf "%s\n" "$(basename "$file")"

        } >> "$history_file"

        printf "%${width}s : true\n"  "Save session"
    else
        printf "%${width}s : false\n"  "Save session"
    fi


    ### Print links
    printf "%${width}s : %s\n"  "Editor" "$link_editor"
    printf "%${width}s : %s\n"   "Lined" "$link_lined"
    printf "%${width}s : %s\n\n" "Plain" "$link_plain"


    ### Links format
    case "$format" in
        all) 
            link_list="$(printf "%s\n%s\n%s\n%s\n" "$link_list" "$link_editor" "$link_lined" "$link_plain")"
            ;;
        editor)
            link_list="$(printf "%s\n%s\n" "$link_list" "$link_editor")"
            ;;
        plain)
            link_list="$(printf "%s\n%s\n" "$link_list" "$link_plain")"
            ;;
        lined)
            link_list="$(printf "%s\n%s\n" "$link_list" "$link_lined")"
            ;;
        none)
            return ;;
    esac
         
}



###############################################################
# Arguments parser
###############################################################

usage()
{
    printf "Usage: %s [OPTIONS] <file1> <file...>\n" "$script_name"
    printf "Try '%s --help' for more information.\n" "$script_name"

    exit 1
}


### The script doesn't like no argument
if [ "$#" -lt 1 ]; then
    usage
fi


### Error function to prevent repetition 
error_arg()
{
    printf "%s: %s unrecognized option\n" "$script_name" "$1"
    printf "Try '%s --help' for more information.\n" "$script_name"

    exit 1
}


### Using variables to store arguments
ARG_OPTIONS="e expire-time f files s save-session"
ARG_FORMAT="o output-format"
ARG_HISTORY="l history L history-table r delete-history"
ARG_DOWNLOAD="d download-url D download-hash R delete-download"
ARG_UTILITIES="c check-link C check-hash"
ARG_MISC="u upgrade U force-upgrade v version h help"

OPTARG=" $ARG_OPTIONS $ARG_FORMAT $ARG_HISTORY"
OPTARG=" $OPTARG $ARG_DOWNLOAD $ARG_UTILITIES $ARG_MISC "


### Check if arguments are valid
for arg in "$@"; do
    arg_single_quote="$(printf "%s" "$arg" | cut -c 1)"
       arg_short_cmd="$(printf "%s" "$arg" | cut -c 2)"

    arg_double_quote="$(printf "%s" "$arg" | cut -c -2)"
        arg_long_cmd="$(printf "%s" "$arg" | cut -c 3-)"

    if [ "$arg_double_quote" = "--" ] ; then 
        if ! echo "$OPTARG" | grep -q -o " $arg_long_cmd " ; then
            error_arg "$arg"
        fi
    elif [ "$arg_single_quote" = "-" ] ; then
        if ! echo "$OPTARG" | grep -q -o " $arg_short_cmd " ; then
            error_arg "$arg"
        fi
    else
       continue
    fi
done



###############################################################
# Functions
###############################################################

while [ $# -gt 0 ]; do
    if [ -f "$1" ]; then
        file_upload "$1"
        file_flag=1
    fi


    case "$1" in
        # Options
        -e|--expire-time)
                shift 1
                expire_time "$1"
                ;;
        -s|--save-session)
                save_session
                ;;
        # Output
        -o|--output-format)
                shift 1
                output_format "$1"
                ;;
        # history
        -l|--history)
                shift 1
                show_history "$1"
                ;;
        -L|--history-table)
                shift 1
                show_history_table "$1"
                ;;
        -r|--delete-history)
                delete_history
                ;;
        # Download
        -d|--download)
                shift 1
                download "$*"
                ;;
        -D|--download-alive)
                shift 1
                download_alive 
                ;;
        # Utilities
        -c|--check)
                shift 1
                check_link "$1"
                ;;
        # Misc
        -u|--upgrade)
                upgrade
                ;;
        -U|--force-upgrade)
                force_upgrade
                ;;
        -h|--help)
                help_page
                ;;
        -v|--version)
                version
                ;;
        #*)
        #        #error "invalid argument"
        #        #usage
        #        ;;
    esac ; shift

done

    if [ "$file_flag" -eq 0 ]; then
        error "no valid file"
    fi


###############################################################
# Link list
###############################################################

if [ -n "$link_list" ]; then
    printf "\n"
    printf "Output format: %s\n" "$format"

    printf "%s\n" "$link_list"
fi

