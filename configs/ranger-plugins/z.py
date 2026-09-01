import re
from ranger.api.commands import Command  # type: ignore
from ranger.ext.spawn import check_output  # type: ignore


class z(Command):
    # cleanup ansi codes returned by iterm's shell integration
    clean_iterm_ansi = re.compile(r'\x1b.*\x07')

    def _zoxide(self, *flags):
        # zoxide is a mise tool with a shell-agnostic CLI — no `zsh -ic`
        # round-trip (which made :z die with FileNotFoundError on hosts
        # without zsh). No keyword prints the highest-ranked entry, matching
        # the old `z -e` / `z --complete` with an empty argument.
        argv = ['zoxide', 'query'] + list(flags)
        if self.arg(1):
            argv.append(self.arg(1))
        return check_output(argv)

    def execute(self):
        directory_with_ansi = self._zoxide()

        directory = self.clean_iterm_ansi.sub(
            '', directory_with_ansi
        ).rstrip('\n')
        self.fm.cd(directory)

    def tab(self, tabnum):
        directories_with_ansi = self._zoxide('--list')

        directories = self.clean_iterm_ansi.sub(
            '', directories_with_ansi
        ).splitlines()
        return [f'z {directory}' for directory in directories]
