#!/bin/bash

clone_repository() {
	local repository="$1"
	local branch="$2"

	local dst
	local err

	if ! dst=$(mktemp --directory); then
		log_error "Could not create temporary directory for git clone"
		return 1
	fi

	if ! err=$(git clone -b "$branch" "$repository" "$dst" 2>&1); then
		log_error "Could not clone $branch#$repository to $dst"
		log_highlight "git clone" <<< "$err" | log_error

		if ! rm -rf "$dst"; then
			log_warn "Could not clean up $dst"
		fi

		return 1
	fi

	echo "$dst"
	return 0
}

compile_contents() {
	local contents="$1"

	local err

	if ! err=$(cd "$contents" && jekyll build); then
		log_error "Could not compile sources in $contents"
		log_highlight "jekyll build" <<< "$err" | log_error
		return 1
	fi

	return 0
}

deploy_contents() {
	local src="$1"
	local dst="$2"

	if ! cp -a "$src/_site/." "$dst/."; then
		log_error "Could not copy $src/_site to $dst"
		return 1
	fi

	return 0
}

compile_and_deploy_contents() {
	local src="$1"
	local dst="$2"

	if ! compile_contents "$src"; then
		log_error "Could not compile contents"
		return 1
	fi

	if ! deploy_contents "$src" "$dst"; then
		log_error "Could not deploy contents"
		return 1
	fi

	return 0
}

handle_commit_msg() {
	local commit_msg="$1"
	local destination="$2"

	local repository
	local branch
	local clone
	local -i err

	err=0

	if ! repository=$(foundry_msg_commit_get_repository "$commit_msg") ||
	   ! branch=$(foundry_msg_commit_get_branch "$commit_msg"); then
		log_info "Dropping malformed commit message"
		return 1
	fi

	if ! clone=$(clone_repository "$repository" "$branch"); then
		log_error "Could not clone $repository#$branch"
		return 1
	fi

	if ! compile_and_deploy_contents "$clone" "$destination"; then
		log_error "Could not deploy $clone to destination"
		err=1
	fi

	if ! rm -rf "$clone"; then
		log_warn "Could not clean up $clone"
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

	opt_add_arg "t" "topic"       "v" "www-commits"           "The topic to listen on"
	opt_add_arg "d" "destination" "v" "/srv/www/m10k.eu/root" "The path to deploy content to"

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
