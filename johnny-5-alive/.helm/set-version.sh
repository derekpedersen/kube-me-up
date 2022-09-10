#!/bin/bash

sed -i -e 's/^version:.*$/version: '$(date '+%Y.%m%d%H%M')'/' -e 's/^appVersion:.*$/appVersion: '$(git rev-parse HEAD)'/' .helm/Chart.yaml
