all:
ifdef path
	v run . $(path) && ./out
else
	v run . && ./out
endif

clean:
	rm out.c out


TESTDIR = examples
test: $(TESTDIR)/*.iris
	for file in $^; do \
		echo "----- compiling $${file} -----"; \
		echo; \
		v run . "./$${file}" && ./out; \
		echo; \
		echo "----- success -----"; \
		echo; \
	done
