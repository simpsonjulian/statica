lint:
	shellcheck statica
	grep bash tools.d/ | xargs shellcheck
	actionlint .github/workflows/*.yml

test: lint
	bundle exec rspec spec
	semgrep --debug --config semgrep/unsupported-platform.yml semgrep
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
