

ifeq ($(OS),Windows_NT)
	VCOMMAND := v.bat
else
	VCOMMAND := v
endif

all:
ifdef path
	${VCOMMAND} run . $(path) && ./out
else
	${VCOMMAND} run . && ./out
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
	done
	rm out.c out
