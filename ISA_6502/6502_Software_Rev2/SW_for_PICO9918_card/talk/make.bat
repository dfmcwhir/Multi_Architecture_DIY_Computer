@echo off
rem Build TALK.BIN with the cc65 tools (ca65 and ld65 on the PATH).
rem The rules: python gen_rules.py (makes rules.inc from nrl_rules.json, words.txt)
ca65 -I .. talk.s -o talk.o -l talk.lst || goto fail
ld65 -C talk.cfg talk.o -o TALK.BIN -m talk.map || goto fail
del talk.o
echo TALK.BIN built.
exit /b 0
:fail
echo TALK.BIN: build failed.
exit /b 1
