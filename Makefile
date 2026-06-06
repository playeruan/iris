all:
ifdef path
	v run . $(path)
else
	v run . > out.c; clang out.c -lraylib -o out; ./out
endif

clean:
	rm out.c out
