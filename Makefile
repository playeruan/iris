all:
ifdef path
	v run . $(path) && ./out
else
	v run . && ./out
endif

clean:
	rm out.c out
