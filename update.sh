#!/usr/bin/env bash
set -Eeuo pipefail

# see https://www.redmine.org/projects/redmine/wiki/redmineinstall
defaultRubyVersion='3.1'
declare -A rubyVersions=(
	[1.2]='2.7'
	[1.3]='2.7'
	[2.0]='2.7'
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

relasesUrl='https://github.com/redmica/redmica/archive'
versionsPage="$(curl -fsSL 'https://github.com/redmica/redmica/releases')"

passenger="$(curl -fsSL 'https://rubygems.org/api/v1/gems/passenger.json' | sed -r 's/^.*"version":"([^"]+)".*$/\1/')"

for version in "${versions[@]}"; do
	fullVersion=$(sed <<<"$versionsPage" -nr "s/.*($version\.[0-9]+)\.tar\.gz[^.].*/\1/p" | sort -V | tail -1)
	url="$relasesUrl/v$fullVersion.tar.gz"
	sha256="$(curl -fsSL "$relasesUrl/v$fullVersion.tar.gz" | sha256sum | cut -d' ' -f1)"

	rubyVersion="${rubyVersions[$version]:-$defaultRubyVersion}"

	text="ruby $rubyVersion"
	doPassenger=
	if [ "$version" = '1.2' -o "$version" = '1.3' -o "$version" = '2.0' ]; then
		text+="; passenger $passenger"
		doPassenger=1
	fi

	echo "$version: $fullVersion ($text)"

	commonSedArgs=(
		-r
		-e 's/%%REDMINE_VERSION%%/'"$fullVersion"'/'
		-e 's/%%RUBY_VERSION%%/'"$rubyVersion"'/'
		-e 's!%%REDMINE_DOWNLOAD_URL%%!'"$url"'!'
		-e 's/%%REDMINE_DOWNLOAD_SHA256%%/'"$sha256"'/'
		-e 's/%%REDMINE%%/iquiw\/redmica:'"$version"'/'
	)

	mkdir -p "$version"
	cp docker-entrypoint.sh "$version/"
	sed "${commonSedArgs[@]}" Dockerfile-debian.template > "$version/Dockerfile"

	if [ -n "$doPassenger" ]; then
		mkdir -p "$version/passenger"
		sed "${commonSedArgs[@]}" \
			-e 's/%%PASSENGER_VERSION%%/'"$passenger"'/' \
			Dockerfile-passenger.template > "$version/passenger/Dockerfile"
	fi

	mkdir -p "$version/alpine"
	cp docker-entrypoint.sh "$version/alpine/"
	sed -i -e 's/gosu/su-exec/g' "$version/alpine/docker-entrypoint.sh"
	sed "${commonSedArgs[@]}" Dockerfile-alpine.template > "$version/alpine/Dockerfile"
done
