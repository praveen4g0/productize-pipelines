
sync-source:
	./sync-source.sh

test-image-builds:
	./release.py -bri true -bt true 

release-images:
	./release.py -bri true

update-csv-image-ref:
	./release.py -ucsv true

publish-operator:
	./release.py -ucsv true -bm true

complete-release:
	./release.py -bri true -ucsv true -bm true

enable-operator:
	./enable-operator.sh
