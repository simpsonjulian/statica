test:
	rspec .
	./statica . html console

clean:
	rm -f *.html *.csv
	rm -rf WebGoat

test.html:
	./html_report.rb spec test.html

spec:
	rspec .

acceptance:
	./acceptance.sh

live:
	./live.sh

.PHONY: test clean test.html spec acceptance live
