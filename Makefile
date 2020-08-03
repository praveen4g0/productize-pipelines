
sync-source:
	./sync-source.sh

test-image-builds:
	./release.py --build-release-images true --build-tests true

release-images:
	./release.py --build-release-images true

publish-operator:
	./release.py --build-metadata true

update-csv-image-ref:
	./release.py ---update-csv true

complete-release:
	./release.py --build-release-images true ---update-csv true --build-metadata true

enable-operator:
	./release.py --enable-operator true
