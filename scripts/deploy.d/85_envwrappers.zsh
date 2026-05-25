# Link each env-wrapper's plugins. rbenv was removed; mise handles ruby.

print "Linking env-wrappers' plugins..."
for env_wrapper in $SCRIPT_DIR/env-wrappers/*; do
    # `plugin` here is a directory whose name doesn't match the env-wrapper's.
    for env_wrapper_plugin in $env_wrapper/^${env_wrapper:t}$*(#qN/); do
        zf_ln -sfn $env_wrapper_plugin $XDG_DATA_HOME/${env_wrapper:t}/plugins/${env_wrapper_plugin:t}
    done
done
zf_ln -sfn $SCRIPT_DIR/env-wrappers/goenv/goenv/plugins/go-build $XDG_DATA_HOME/goenv/plugins/go-build
zf_ln -sfn $SCRIPT_DIR/env-wrappers/jenv/jenv/available-plugins/export $XDG_DATA_HOME/jenv/plugins/export
zf_ln -sfn $SCRIPT_DIR/env-wrappers/pyenv/default-packages $XDG_DATA_HOME/pyenv/default-packages
print "  ...done"
