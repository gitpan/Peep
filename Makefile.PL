use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Peep',
    'VERSION_FROM'	=> 'Peep.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    'PM'                => {
                            '../bin/peck' => '$(INST_SCRIPT)/peck',
                            '../bin/logparser' => '$(INST_SCRIPT)/logparser',
                            '../bin/sysmonitor' => '$(INST_SCRIPT)/sysmonitor',
                            '../bin/keytest' => '$(INST_SCRIPT)/keytest',
                           },
);
