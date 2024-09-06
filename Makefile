test:
	./statica . html

clean:
	rm -f *.html

test.html:
	./html_report.rb spec test.html

spec:
	rspec .

.PHONEY: test clean test.html spec

