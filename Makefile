# brew scratch builds
test-image-builds:
	./release.py --build-release-images true --build-tests true

sync-source:
	./sync-source.sh

# brew builds
release-images:
	./release.py --build-release-images true

# create a new-csv based on an already existing csv
# the new csv will nave placeholders for image references, which will
# be populated later by the `make update-csv-iamge-ref
new-csv:
ifndef CSV_VERSION
	@echo CSV_VERSION not defined
	@exit 1
endif
ifndef FROM_CSV_VERSION
	@echo FROM_CSV_VERSION not defined
	@exit 1
endif
ifndef OPERATOR_CHANNEL_NAME
	@echo OPERATOR_CHANNEL_NAME not defined
	@exit 1
endif
	./release.py --new-csv true \
	--csv-version  ${CSV_VERSION} \
	--from-csv-version  ${FROM_CSV_VERSION} \
	--operator-release-channel ${OPERATOR_CHANNEL_NAME}

# update the ImageReferences in the CSV (to be released) using the latest brew builds
# the target csv file is chosen based on `csv-semver` param in `image-config.yaml`
update-csv-image-ref:
ifndef CSV_VERSION
	@echo CSV_VERSION not defined
	@exit 1
endif
	./release.py --update-csv true \
	--csv-version  ${CSV_VERSION}

# build operator-metadata image in brew
# this will create an image (non-executable) which will contain our csv bundle
# suceessful build of this image will inturn result in the
# pre-stage publication of the operator
publish-operator:
	./release.py --build-metadata true

# handle with care :)
complete-release: release-images update-csv-image-ref publish-operator

# mirror the images required for testing the operator
enable-operator:
ifndef CSV_VERSION
	@echo CSV_VERSION not defined
	@exit 1
endif
	./release.py --enable-operator true \
	--csv-version  ${CSV_VERSION}
