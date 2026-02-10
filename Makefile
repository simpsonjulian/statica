lint:
	shellcheck statica
	file tools.d/* | grep 'shell script' | awk -F ':' '{print $$1}' | xargs shellcheck
	actionlint .github/workflows/*.yml

test: lint
	bundle exec rspec spec
	semgrep-rules-manager update
	semgrep --debug --config p/ci --include spec --include . .
	./statica . html

clean:
	rm -f *.html *.csv
	rm -rf WebGoat

test.html:
	./html_report.rb spec test.html

acceptance:
	./acceptance.sh

live:
	./live.sh

.PHONY: test clean test.html spec acceptance live selftest
