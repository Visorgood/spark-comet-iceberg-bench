#!/usr/bin/env bash
# One-time setup. Everything it downloads or builds goes to deps/ unless env.local.sh
# points to existing installs.
#
#   1. Checks Java 17 or 21, Python 3, curl, git.
#   2. Spark: downloads spark-$SPARK_VERSION-bin-hadoop3.tgz from archive.apache.org,
#      verifies its SHA-512, unpacks it to deps/. Skipped if $SPARK_HOME already has Spark.
#   3. tpchgen-cli: checks it is installed in version $TPCHGEN_VERSION (does not install it).
#   4. Comet, first match wins:
#        - COMET_JAR set in env.local.sh: used as is;
#        - COMET_RELEASE set, Linux: downloads the published jar from Maven Central (SHA-1 checked);
#        - COMET_RELEASE set, macOS: downloads the release source from dist.apache.org
#          (SHA-512 checked) and runs `make release-nogit`;
#        - otherwise: clones apache/datafusion-comet into deps/ at COMET_REF and runs `make release`.
#          If COMET_HOME points to your own checkout, its git state is never changed.
#   5. Writes out/$MACHINE_ID/versions.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source scripts/lib.sh

need() { command -v "$1" >/dev/null || { echo "Missing: $1. $2" >&2; exit 1; }; }
need java "Install JDK 17 or 21."
need python3 "Install Python 3.9 or newer."
need curl ""
need git ""
JAVA_MAJOR="$(java -version 2>&1 | awk -F'"' '/version/ {split($2, v, "."); print v[1]; exit}')"
case "$JAVA_MAJOR" in
  17|21) echo "== Java $JAVA_MAJOR" ;;
  *) echo "Java $JAVA_MAJOR found; Spark $SPARK_VERSION with Comet needs 17 or 21." >&2; exit 1 ;;
esac
mkdir -p "$DEPS_DIR" "$DATA_DIR" "$WAREHOUSE" "$EVENTS_DIR" "$OUT_DIR/$MACHINE_ID" "$RESULTS_DIR"

# --- Spark -----------------------------------------------------------------------
if [ ! -x "$SPARK_HOME/bin/spark-submit" ]; then
  NAME="spark-${SPARK_VERSION}-bin-hadoop3"
  URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${NAME}.tgz"
  echo "== Downloading $URL"
  curl -fL -o "$DEPS_DIR/$NAME.tgz" "$URL"
  curl -fL -o "$DEPS_DIR/$NAME.tgz.sha512" "$URL.sha512"
  verify_checksum "$DEPS_DIR/$NAME.tgz" "$DEPS_DIR/$NAME.tgz.sha512" sha512
  mkdir -p "$(dirname "$SPARK_HOME")"
  tar xzf "$DEPS_DIR/$NAME.tgz" -C "$(dirname "$SPARK_HOME")"
fi
"$SPARK_HOME/bin/spark-submit" --version 2>&1 | grep -m1 -i "version"

# --- tpchgen-cli -------------------------------------------------------------------
if ! command -v tpchgen-cli >/dev/null || ! tpchgen-cli --version | grep -q "$TPCHGEN_VERSION"; then
  echo "tpchgen-cli $TPCHGEN_VERSION is required. Install it with one of:" >&2
  echo "   cargo install tpchgen-cli --version $TPCHGEN_VERSION --locked" >&2
  echo "   pipx install tpchgen-cli==$TPCHGEN_VERSION" >&2
  exit 1
fi

# --- Comet -------------------------------------------------------------------------
OS="$(uname -s)"
build_comet() {  # $1 = source dir, $2 = make target
  need cargo "Install Rust with https://rustup.rs to build Comet."
  echo "== Building Comet in $1 ($2, release mode). This takes a while."
  (cd "$1" && make "$2" PROFILES="-Pspark-4.1" COMET_FEATURES="${COMET_FEATURES:-}")
}

if find_comet_jar && [ "${REBUILD_COMET:-0}" != "1" ]; then
  echo "== Using Comet jar $COMET_JAR"
elif [ -n "$COMET_RELEASE" ] && [ "$OS" = "Linux" ]; then
  JAR="comet-spark-spark4.1_${SCALA_BINARY}-${COMET_RELEASE}.jar"
  URL="https://repo1.maven.org/maven2/org/apache/datafusion/comet-spark-spark4.1_${SCALA_BINARY}/${COMET_RELEASE}/${JAR}"
  echo "== Downloading $URL"
  curl -fL -o "$DEPS_DIR/$JAR" "$URL"
  curl -fL -o "$DEPS_DIR/$JAR.sha1" "$URL.sha1"
  verify_checksum "$DEPS_DIR/$JAR" "$DEPS_DIR/$JAR.sha1" sha1
elif [ -n "$COMET_RELEASE" ]; then
  # Published jars are Linux-only; on macOS build the official source release.
  SRC="apache-datafusion-comet-${COMET_RELEASE}"
  URL="https://dist.apache.org/repos/dist/release/datafusion/datafusion-comet-${COMET_RELEASE}/${SRC}.tar.gz"
  if [ ! -d "$DEPS_DIR/$SRC" ]; then
    echo "== Downloading $URL"
    curl -fL -o "$DEPS_DIR/$SRC.tar.gz" "$URL"
    curl -fL -o "$DEPS_DIR/$SRC.tar.gz.sha512" "$URL.sha512"
    verify_checksum "$DEPS_DIR/$SRC.tar.gz" "$DEPS_DIR/$SRC.tar.gz.sha512" sha512
    tar xzf "$DEPS_DIR/$SRC.tar.gz" -C "$DEPS_DIR"
  fi
  COMET_HOME="$DEPS_DIR/$SRC"
  build_comet "$COMET_HOME" release-nogit
else
  case "$COMET_HOME" in
    "$DEPS_DIR"/*)
      if [ ! -d "$COMET_HOME/.git" ]; then
        git clone https://github.com/apache/datafusion-comet.git "$COMET_HOME"
      fi
      (cd "$COMET_HOME" && git fetch -q origin && git checkout -q "$COMET_REF")
      ;;
    *)
      HEAD="$(cd "$COMET_HOME" && git rev-parse HEAD)"
      if [ "$HEAD" != "$COMET_REF" ]; then
        echo "WARNING: $COMET_HOME is at $HEAD, not COMET_REF $COMET_REF." >&2
        echo "         Results will not match the published ones. This script does not change your checkout." >&2
      fi
      ;;
  esac
  build_comet "$COMET_HOME" release
fi
find_comet_jar || { echo "Comet jar not found after setup." >&2; exit 1; }
echo "== Comet jar: $COMET_JAR"

# --- Record versions ---------------------------------------------------------------
{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "spark: $SPARK_VERSION ($SPARK_HOME)"
  echo "iceberg: $ICEBERG_VERSION"
  echo "tpchgen-cli: $(tpchgen-cli --version)"
  echo "java: $(java -version 2>&1 | head -1)"
  echo "comet_release: ${COMET_RELEASE:-none}"
  if [ -d "$COMET_HOME/.git" ]; then echo "comet_commit: $(cd "$COMET_HOME" && git rev-parse HEAD)"; fi
  echo "comet_jar: $(basename "$COMET_JAR")"
  echo "comet_jar_sha256: $(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$COMET_JAR")"
  echo "comet_features: ${COMET_FEATURES:-system allocator}"
} | tee "$OUT_DIR/$MACHINE_ID/versions.txt"
echo "== Ready. Next: bash scripts/05_machine_info.sh"
