#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

set -e
git config --global --add safe.directory /pulsar

ROOT_DIR=$(git rev-parse --show-toplevel)
cd $ROOT_DIR/pulsar-client-cpp

JAVA_HOME=/usr ./pulsar-test-service-start.sh


pushd tests

export RETRY_FAILED="${RETRY_FAILED:-1}"

if [ -f /gtest-parallel/gtest-parallel ]; then
    gtest_workers=10
    # use nproc to set workers to 2 x the number of available cores if nproc is available
    if [ -x "$(command -v nproc)" ]; then
      gtest_workers=$(( $(nproc) * 2 ))
    fi
    # set maximum workers to 10
    gtest_workers=$(( gtest_workers > 10 ? 10 : gtest_workers ))
    echo "---- Run unit tests in parallel (workers=$gtest_workers) (retry_failed=${RETRY_FAILED})"
    tests=""
    if [ $# -eq 1 ]; then
        tests="--gtest_filter=$1"
        echo "Running tests: $1"
    fi
    python3 /gtest-parallel/gtest-parallel $tests --dump_json_test_results=/tmp/gtest_parallel_results.json \
      --workers=$gtest_workers --retry_failed=$RETRY_FAILED -d /tmp \
      ./main --gtest_filter='-CustomLoggerTest*'
    # The customized logger might affect other tests
    ./main --gtest_filter='CustomLoggerTest*'
    RES=$?
else
    ./main
    RES=$?
fi

popd

if [ $RES -eq 0 ]; then
    pushd python
    echo "---- Build Python Wheel file"
    python3 setup.py bdist_wheel

    echo "---- Installing Python Wheel file"
    ls -lha dist
    WHEEL_FILE=$(ls dist/ | grep whl)
    echo "${WHEEL_FILE}"
    echo "dist/${WHEEL_FILE}[all]"
    pip3 install dist/${WHEEL_FILE}[all]

    echo "---- Running Python unit tests"

    # Running tests from a different directory to avoid importing directly
    # from the current dir, but rather using the installed wheel file
    cp *_test.py /tmp
    pushd /tmp

    python3 custom_logger_test.py
    RES=$?
    echo "custom_logger_test.py: $RES"

    python3 pulsar_test.py
    RES=$?
    echo "pulsar_test.py: $RES"

    echo "---- Running Python Function Instance unit tests"
    bash $ROOT_DIR/pulsar-functions/instance/src/scripts/run_python_instance_tests.sh
    RES=$?
    echo "run_python_instance_tests.sh: $RES"

    popd
    popd
fi

./pulsar-test-service-stop.sh

exit $RES
