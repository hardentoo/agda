TOP = ../..

include $(TOP)/mk/paths.mk

# Enable read -n and 2>&1 |.
SHELL=/usr/bin/env bash

# Get the current directory (OS dependent).
uname:=$(shell uname)
ifeq (NT-5,$(findstring NT-5,$(uname)))
pwd=$(shell (cmd /c 'echo %CD%') | sed -e 's/\\/\\\\\\\\/g')
pwdPlusDelimiter=$(pwd)\\\\
else
pwd=$(shell pwd)
pwdPlusDelimiter=$(pwd)/
endif

# use gsed on Mac OS instead of sed
ifeq (Darwin,$(findstring Darwin,$(uname)))
sed=gsed
else
sed=sed
endif

clean=/usr/bin/env bash $(shell pwd)/clean.sh $(sed)

# Construct the list of tests to carry out.
# Andreas, 2017-04-24 ls -t: sort by newest first
AgdaFiles=$(shell ls -t *agda)
OutFiles=$(patsubst %.lagda,%.out,$(patsubst %.agda,%.out,$(AgdaFiles)))
Tests=$(patsubst %.lagda,%.cmp,$(patsubst %.agda,%.cmp,$(AgdaFiles)))

default : $(Tests)

export TMPDIR=highlighting-tmp

# Filter out absolute pathes, make all whitespace equal, remove
# "Linking..." messages since GHC 7.0 doesn't have them.
filter=$(sed) -e 's"$(pwdPlusDelimiter)""g' \
              -e 's"$(pwd)""g' \
              -e 's" \"$(TMPDIR).*\"""' \
              -e 's"[^ (\"]*lib.prim"agda-default-include-path"g' \
              -e 's/\((agda2-info-action "\*Agda Version\*" "Agda version \([[:digit:]]\+\.\)\+[[:digit:]]\+\)\(-[[:alnum:]]\+\(-dirty\)\?\)\?\(" nil)\)/\1\5/g' \
              -e 's/\(\\n\| \)\+/ /g' \
              -e 's/^ //g' \
              -e '/Linking /d' \
              -e 's/Agda2> //g' \
     | $(clean)

run_test=if test -f $*.in; \
    then cat $*.in \
         | $(sed) "s/ioTCM/IOTCM/g" \
         | $(sed) "s/cmd_give/(cmd_give WithoutForce)/g" \
         | $(sed) "s/cmd_/Cmd_/g" \
         | $(sed) "s/showImplicitArgs/ShowImplicitArgs/g" \
         | $(sed) "s/toggleImplicitArgs/ToggleImplicitArgs/g" \
         | $(sed) "s/top_command/IOTCM currentFile None Indirect/g" \
         | $(sed) "s/goal_command \\([0-9]\+\\) (\\([^)]\+\\)) \\(\"[^\"]*\"\\)/IOTCM currentFile None Indirect (\\2 \\1 noRange \\3)/g" \
         | $(sed) "s/goal_command \\([0-9]\+\\) \\([^ ]\+\\) \\(\"[^\"]*\"\\)/IOTCM currentFile None Indirect (\\2 \\1 noRange \\3)/g" \
         | $(sed) "s/currentFile/\"$(wildcard $*.agda $*.lagda)\"/g" \
         | $(AGDA_BIN) -i . -i .. --interaction --ignore-interfaces --no-default-libraries $(RTS_$*) \
           2>&1 | $(filter) ; \
    elif test -f $*.hs; \
    then /usr/bin/env runhaskell ./$*.hs $(AGDA_BIN) 2>&1 | $(filter) ; \
    else /usr/bin/env bash ./$*.sh $(AGDA_BIN) > $(TMPDIR)/$*.tmp_out ; \
         cat $(TMPDIR)/$*.tmp_out | $(filter) ; \
    fi

# Note that RTS_... variables are ignored when .hs/.sh files are used.

setup_Issue591     = rm -f Issue591/M.agdai
setup_Issue2217    = rm -f Issue2217/M.agdai
setup_Highlighting = rm -f Highlighting/M.agdai
setup_Auto = $(AGDA_BIN) Auto/Prelude.agda
setup_Auto-BasicLogic = $(setup_Auto)
setup_Auto-DataConstruction = $(setup_Auto)
setup_Auto-EqualityReasoning = $(setup_Auto)
setup_Auto-IndexedDatatypes = $(setup_Auto)
setup_Auto-Misc = $(setup_Auto)
setup_Auto-Modules = $(setup_Auto)
cleanup_Issue373   = rm -rf Issue373 MAlonzo
cleanup_Issue2714  = rm -rf MAlonzo
cleanup_CompilationWarnings = rm -rf MAlonzo
setup_QuickLaTeX-Caching = rm -rf latex
cleanup_QuickLaTeX-Caching = rm -rf latex
RTS_Issue637       = +RTS -K10000 -RTS
RTS_Issue639       = --safe
RTS_Issue1785      = --library-file=issue1785.libs

# No recorded output
########################################################################

# Andreas, 2017-01-27, issue #2438
# The following rule does not work on my system.
#
#   $(OutFiles) : %.out : $(wildcard %.agda %.lagda) $(wildcard %.in %.in_ghci)
#
# According to the gnu-make manual, the wildcard command matches
# immediately, but files like %.agda or %.lagda is not what we are looking for.
# It would work if pattern matching (%) is done first.
#
# However, we can use second expansion, following
# http://make.mad-scientist.net/secondary-expansion/.
# The evaluation of the automatic variable $@ is first delayed,
# such that it remains as literal string.
# After the pattern matches, and $@ is instantiated to the stem of the target
# say Issue123, we force evaluation of Issue123*.agda which gives us
# the .agda or .lagda file.

.SECONDEXPANSION:
$(OutFiles) : %.out : $$($$@.*agda) $$($$@.in $$@.hs $$@.sh)
	@-mkdir $(TMPDIR)
	@$(setup_$*)
	@rm -f "$(@:.out=.agdai)"
	@echo "=== Output for $* ==="
	@$(run_test) > $@
	@cat $@
	@echo "=== End of output ==="
	@rm -rf $(TMPDIR)

#			diff -b $*.out $*.tmp;

# Comparing output
########################################################################

$(Tests) : %.cmp : %.out
	@-mkdir $(TMPDIR)
	@$(setup_$*)
	@rm -f "$(@:.cmp=.agdai)"
	@echo $*
	@$(run_test) > $*.tmp
	@if diff -b $*.out $*.tmp; \
		then rm -f $*.tmp; true; \
		else \
			echo "=== Old output ==="; \
			cat $*.out; \
			echo "=== New output ==="; \
			cat $*.tmp; \
			echo "=== Diff ==="; \
			wdiff $*.out $*.tmp | colordiff; \
			echo -n "Accept new error [y/N/q]? "; \
			read -n 1; \
			echo ""; \
			if [ "fckShPrg$$REPLY" != "fckShPrgy"  ]; \
			  then echo "Keeping old output"; \
			       rm -f $*.tmp; \
                               rm -rf $(TMPDIR); \
			       if [ "$(cleanup_$*)" != "" ]; then $(cleanup_$*)"" ; fi ; \
			       [ "X$$REPLY" != "Xq" ]; \
			  else echo "Replacing output, continuing..."; \
			    mv $*.tmp $*.out; \
			    true; \
			fi; \
	 fi
	@$(cleanup_$*)
	@rm -rf $(TMPDIR)
