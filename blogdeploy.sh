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

override_jekyll_baseurl() {
	local contents="$1"
	local baseurl="$2"

	local config

	config="$contents/_config.yml"

	if ! sed -i -e "s|^baseurl:.*|baseurl: \"$baseurl\"|g" "$config"; then
		return 1
	fi

	return 0
}

append_to_jekyll_url() {
	local contents="$1"
	local append="$2"

	local config
	local query

	config="$contents/_config.yml"
	query=$(printf 's|^url:[ ]\\+"\\([^"]\\+\\)|url: "\\1%s|g' "$append")

	if ! sed -i -e "$query" "$config"; then
		return 1
	fi

	return 0
}

compile_contents() {
	local contents="$1"
	local branch="$2"

	local err

	if [[ "$branch" == "unstable" ]]; then
		override_jekyll_baseurl "$contents" "/unstable"
	fi

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
	local branch="$3"

	if ! compile_contents "$src" "$branch"; then
		log_error "Could not compile contents"
		return 1
	fi

	if ! deploy_contents "$src" "$dst"; then
		log_error "Could not deploy contents"
		return 1
	fi

	return 0
}

blog_deploy() {
	local repository="$1"
	local branch="$2"
	local destination="$3"

	local clone
	local -i err

	err=0

	if ! clone=$(clone_repository "$repository" "$branch"); then
		log_error "Could not clone $repository#$branch"
		return 1
	fi

	if ! compile_and_deploy_contents "$clone" "$destination" "$branch"; then
		log_error "Could not deploy $clone to destination"
		err=1
	fi

	if ! rm -rf "$clone"; then
		log_warn "Could not clean up $clone"
	fi

	return 0
}

main() {
	local repository
	local branch
	local destination

	opt_add_arg "r" "repository"  "rv" "" "The repository to deploy from"
	opt_add_arg "b" "branch"      "rv" "" "The branch to deploy from"
	opt_add_arg "d" "destination" "rv" "" "The directory to deploy to"

	if ! opt_parse "$@"; then
		return 1
	fi

	repository=$(opt_get "repository")
	branch=$(opt_get "branch")
	destination=$(opt_get "destination")

	if ! blog_deploy "$repository" "$branch" "$destination"; then
		return 1
	fi

	return 0
}

{
	if ! . toolbox.sh ||
	   ! include "log" "opt"; then
		exit 1
	fi

	main "$@"
	exit "$?"
}
