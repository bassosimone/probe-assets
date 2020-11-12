#!/bin/bash
set -e
set -o pipefail

export GO111MODULE=off

assets_go=assets.go
asn_database_name=asn.mmdb
country_database_name=country.mmdb
sha256sums=SHA256SUMS

# assets_get_geoip downloads the country and ASN databases.
#
# We're currently stuck in a situation where we're using db-ip.com for the
# country and an ASN database generated by us. The process with which we are
# generating such database will be made open source soon.
#
# See <https://github.com/ooni/probe-engine/issues/269> and
#     <https://github.com/ooni/asn-db-generator>.
assets_get_geoip() {
    echo "* Fetching geoip databases"
    dbip_country_database_name=dbip-country-lite-2020-11.mmdb
    curl -fsSLO https://download.db-ip.com/free/$dbip_country_database_name.gz
    gunzip $dbip_country_database_name.gz
    mv $dbip_country_database_name $country_database_name
    if [ ! -f $asn_database_name ]; then
        echo "FATAL: please put asn.mmdb on the toplevel directory" 1>&2
        exit 1
    fi
}

# assets_rewrite_assets_go rewrites $assets_go
assets_rewrite_assets_go() {
  echo "* Updating $assets_go"
  rm -rf $assets_go
  echo "package resources"                                          >> $assets_go
  echo ""                                                           >> $assets_go
  echo "const ("                                                    >> $assets_go
  echo "  // Version contains the assets version."                  >> $assets_go
  echo "  Version = $1"                                             >> $assets_go
  echo ""                                                           >> $assets_go
  echo "  // ASNDatabaseName is the ASN-DB file name"               >> $assets_go
  echo "  ASNDatabaseName = \"$asn_database_name\""                 >> $assets_go
  echo ""                                                           >> $assets_go
  echo "  // CountryDatabaseName is country-DB file name"           >> $assets_go
  echo "  CountryDatabaseName = \"$country_database_name\""         >> $assets_go
  echo ""                                                           >> $assets_go
  echo "  // BaseURL is the asset's repository base URL"            >> $assets_go
  echo "  BaseURL = \"https://github.com/\""                        >> $assets_go
  echo ")"                                                          >> $assets_go
  echo ""                                                           >> $assets_go
  echo "// ResourceInfo contains information on a resource."        >> $assets_go
  echo "type ResourceInfo struct {"                                 >> $assets_go
  echo "  // URLPath is the resource's URL path."                   >> $assets_go
  echo "  URLPath string"                                           >> $assets_go
  echo ""                                                           >> $assets_go
  echo "  // GzSHA256 is used to validate the downloaded file."     >> $assets_go
  echo "  GzSHA256 string"                                          >> $assets_go
  echo ""                                                           >> $assets_go
  echo "  // SHA256 is used to check whether the assets file"       >> $assets_go
  echo "  // stored locally is still up-to-date."                   >> $assets_go
  echo "  SHA256 string"                                            >> $assets_go
  echo "}"                                                          >> $assets_go
  echo ""                                                           >> $assets_go
  echo "// All contains info on all known assets."                  >> $assets_go
  echo "var All = map[string]ResourceInfo{"                         >> $assets_go
  for name in $asn_database_name $country_database_name; do
    local gzsha256=$(grep $name.gz$ $sha256sums | awk '{print $1}')
    local sha256=$(grep $name$ $sha256sums | awk '{print $1}')
    if [ -z $gzsha256 -o -z $sha256 ]; then
      echo "FATAL: cannot get GzSHA256 or SHA256" 1>&2
      exit 1
    fi
    echo "    \"$name\": {"                                                      >> $assets_go
    echo "      URLPath: \"/ooni/probe-assets/releases/download/$1/$name.gz\","  >> $assets_go
    echo "      GzSHA256: \"$gzsha256\","                                        >> $assets_go
    echo "      SHA256: \"$sha256\","                                            >> $assets_go
    echo "    },"                                                                >> $assets_go
  done
  echo "}"                                                        >> $assets_go
  go fmt $assets_go
}

rm -rf assets
mkdir assets
version=`date +%Y%m%d%H%M%S`
assets_get_geoip
mv $asn_database_name assets/
mv $country_database_name assets/
rm -rf $sha256sums
shasum -a 256 assets/*                                           >> $sha256sums
go build -v ./cmd/gzipidempotent
(
  set -x
  cd assets
  ../gzipidempotent
)
for file in assets/*.gz; do
  gunzip -c $file > AAA_temporary
  cmp $(echo $file|sed 's/.gz$//g') AAA_temporary
  rm AAA_temporary
done
shasum -a 256 assets/*.mmdb.gz                                   >> $sha256sums
if git diff --quiet; then
  echo "Nothing changed, nothing to do."
  exit 0
fi
assets_rewrite_assets_go $version
git add $sha256sums $assets_go
echo "# To continue with the release run"
echo "- git commit -am \"Release $version\""
echo "- git tag -sm \"ooni/probe-assets $version\" $version"
echo "- git push origin master $version"
