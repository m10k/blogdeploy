#!/bin/bash

handle_commit_msg() {
	local commit_msg="$1"
	local destination="$2"

	local repository
	local branch
	local err

	if ! repository=$(foundry_msg_commit_get_repository "$commit_msg") ||
	   ! branch=$(foundry_msg_commit_get_branch "$commit_msg"); then
		log_info "Dropping malformed commit message"
		return 1
	fi

	if ! err=$(./blogdeploy.sh --repository  "$repository" \
	                           --branch      "$branch"     \
	                           --destination "$destination"); then
		log_error "Could not deploy $repository#$branch to $destination"
		return 1
	fi

	return 0
}

await_commits() {
	local topic="$1"
	local destination="$2"

	local endpoint

	if ! endpoint=$(ipc_endpoint_open); then
		log_error "Could not open an IPC endpoint"
		return 1
	fi

	if ! ipc_endpoint_subscribe "$endpoint" "$topic"; then
		log_error "Could not subscribe to $topic"
	else
		while inst_running; do
			local msg

			if ! msg=$(ipc_endpoint_recv "$endpoint" 5); then
				continue
			fi

			handle_commit "$msg" "$destination"
		done
	fi

	ipc_endpoint_close "$endpoint"

	return 0
}

main() {
	local topic
	local destination

	opt_add_arg "t" "topic"       "v" "www-commits"        "The topic to listen on"
	opt_add_arg "d" "destination" "v" "/srv/www/m10k/root" "The path to deploy content to"

	if ! opt_parse "$@"; then
		return 1
	fi

	topic=$(opt_get "topic")
	destination=$(opt_get "destination")

	inst_singleton await_commits "$topic" "$destination"
	return 0
}

{
	if ! . toolbox.sh ||
	   ! include "log" "opt" "inst" "ipc" "foundry/msg"; then
		exit 1
	fi

	main "$@"
	exit "$?"
}
