lint:
	shellcheck statica
	file tools.d/* | grep 'shell script' | awk -F ':' '{print $$1}' | xargs shellcheck
	actionlint .github/workflows/*.yml

test: lint
	bundle exec rspec spec
	bundle exec ./statica . html

clean:
	rm -f *.html *.csv
	rm -rf WebGoat

test.html:
	./html_report.rb spec test.html

acceptance:
	./acceptance.sh

live:
	./live.sh

docker-build:
	docker build -t statica:latest .

docker-test:
	docker run --rm -v $$(pwd):/app statica:latest statica /app html

.PHONY: test clean test.html spec acceptance live selftest docker-build docker-test
