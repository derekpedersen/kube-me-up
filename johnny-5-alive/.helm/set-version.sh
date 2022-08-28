#!/bin/bash

sed -i -e 's/^version:.*$/version: '$(date '+%Y.%m%d%H%M')'/' -e 's/^appVersion:.*$/appVersion: '$(git rev-parse HEAD)'/' .helm/http/Chart.yaml

sed -i -e 's/^version:.*$/version: '$(date '+%Y.%m%d%H%M')'/' -e 's/^appVersion:.*$/appVersion: '$(git rev-parse HEAD)'/' .helm/https/Chart.yaml
