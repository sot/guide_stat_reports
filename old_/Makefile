# Set the task name
TASK = gui_stat_reports

# set a version for the "make dist" option
VERSION = 1.0

# Uncomment the correct choice indicating either SKA or TST flight environment
FLIGHT_ENV = SKA


include /proj/sot/ska/include/Makefile.FLIGHT

SHARE = gui_stat_reports.py make_toc.pl gui_summarize.py star_error.py
TEMPLATES = templates/index.html templates/stars.html templates/summary.html
DATA = task_schedule.cfg make_likelihood_fit.py 

install:
ifdef TEMPLATES
	mkdir -p $(INSTALL_SHARE)/templates/
	rsync --times --cvs-exclude $(TEMPLATES) $(INSTALL_SHARE)/templates/
endif
ifdef SHARE
	mkdir -p $(INSTALL_SHARE)
	rsync --times --cvs-exclude $(SHARE) $(INSTALL_SHARE)/
endif
ifdef BIN
	mkdir -p $(INSTALL_BIN)
	rsync --times --cvs-exclude $(BIN) $(INSTALL_BIN)/
endif
ifdef DATA
	mkdir -p $(INSTALL_DATA)
	rsync --times --cvs-exclude $(DATA) $(INSTALL_DATA)/
endif
ifdef CGI
	mkdir -p $(CGI_DIR)
	rsync --times --cvs-exclude $(CGI) $(CGI_DIR)/
endif
ifdef WEB
	mkdir -p $(WEB_DIR)
	rsync --times --cvs-exclude $(WEB) $(WEB_DIR)/
endif
ifdef LIB
	mkdir -p $(INSTALL_PERLLIB)/Ska/
	rsync --times --cvs-exclude $(LIB) $(INSTALL_PERLLIB)/Ska/
endif
ifdef PROJLIB
	mkdir -p $(INSTALL_PERLLIB)/Ska/$(PERLTASK)/
	rsync --times --cvs-exclude $(PROJLIB) $(INSTALL_PERLLIB)/Ska/$(PERLTASK)/
endif

