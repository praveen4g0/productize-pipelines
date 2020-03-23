
sync-source:
	./sync-source.sh

test-image-builds: 
	./release.sh -b true -t true 

release-images: 
	./release.sh -b true

update-csv-image-ref:
	./release.sh

make release-meta:
	./meta.sh

publish-operator:
	./release.sh -p true

enable-operator:
	./enable-operator.sh
