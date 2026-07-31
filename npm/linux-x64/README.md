# @rabadon/linux-x64

Prebuilt rabadon native binaries for **linux/x64**. You do not install this
directly — the [`rabadon`](https://www.npmjs.com/package/rabadon) package
lists it as an `optionalDependencies` entry and npm picks the one matching
your platform. If no prebuilt matches, `rabadon`'s postinstall builds the
same binaries from source.
