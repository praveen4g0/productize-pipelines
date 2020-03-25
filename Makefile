
sync-source:
	./sync-source.sh

test-image-builds:
	./release.py -b true -t true 

release-images:
	./release.py -b true

update-csv-image-ref:
	./release.py

make release-meta:
	./meta.sh

publish-operator:
	./release.py -p true

enable-operator:
	./enable-operator.sh
