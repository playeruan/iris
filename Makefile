all:
ifdef path
	v run . $(path)
else
	v run .
endif
