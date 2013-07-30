# ncm-ncd

Front end for executing Quattor configuration modules.

## Uses

### Running specific configuration modules

To run a well-defined list of configuration modules together with
their pre and post-dependencies, do:

```bash
$ ncm-ncd --configure <module1> [<module2> ...]
```

### Running all configuration modules

Use the `--all` option:

```bash
$ ncm-ncd --configure --all
```

### Listing available components

Use the `--list` option.  It is incompatible with `--configure`.

```bash
$ ncm-ncd --list
```

## See also

Full help with `ncm-ncd --help`
