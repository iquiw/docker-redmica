#!/usr/bin/env bash
set -Eeuo pipefail

# see https://www.redmine.org/projects/redmine/wiki/redmineinstall
defaultRubyVersion='2.7'
declare -A rubyVersions=(
	[1.0]='2.6'
	[1.1]='2.6'
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
	sha256="$(curl -fsSL "$relasesUrl/v$fullVersion.tar.gz" | sha256sum | cut -d' ' -f1)"

	rubyVersion="${rubyVersions[$version]:-$defaultRubyVersion}"

	echo "$version: $fullVersion (ruby $rubyVersion; passenger $passenger)"

	commonSedArgs=(
		-r
		-e 's/%%REDMINE_VERSION%%/'"$fullVersion"'/'
		-e 's/%%RUBY_VERSION%%/'"$rubyVersion"'/'
		-e 's/%%REDMINE_DOWNLOAD_SHA256%%/'"$sha256"'/'
		-e 's/%%REDMINE%%/iquiw\/redmica:'"$version"'/'
		-e 's/%%PASSENGER_VERSION%%/'"$passenger"'/'
	)
	alpineSedArgs=()

	# https://github.com/docker-library/redmine/pull/184
	# https://www.redmine.org/issues/22481
	# https://www.redmine.org/issues/30492
	if [ "$version" = 4.0 ]; then
		commonSedArgs+=(
			-e '/ghostscript /d'
			-e '\!ImageMagick-6/policy\.xml!d'
		)
		alpineSedArgs+=(
			-e 's/imagemagick/imagemagick6/g'
		)
	else
		commonSedArgs+=(
			-e '/imagemagick-dev/d'
			-e '/libmagickcore-dev/d'
			-e '/libmagickwand-dev/d'
		)
	fi

	mkdir -p "$version"
	cp docker-entrypoint.sh "$version/"
	sed "${commonSedArgs[@]}" Dockerfile-debian.template > "$version/Dockerfile"

	mkdir -p "$version/passenger"
	sed "${commonSedArgs[@]}" Dockerfile-passenger.template > "$version/passenger/Dockerfile"

	mkdir -p "$version/alpine"
	cp docker-entrypoint.sh "$version/alpine/"
	sed -i -e 's/gosu/su-exec/g' "$version/alpine/docker-entrypoint.sh"
	sed "${commonSedArgs[@]}" "${alpineSedArgs[@]}" Dockerfile-alpine.template > "$version/alpine/Dockerfile"
done
