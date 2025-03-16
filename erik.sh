#!/bin/bash



usage() {
  echo "Usage: $0 <path to app source>"
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
fi

REPO_PATH=$1
set -euo pipefail


#TODO: get default branch
#MAIN_BRANCH=develop

# Set the repository path and the output file for the stats

OUTPUT_FILE="scc_stats.csv"
SCC_COMMAND="scc  --no-cocomo --no-size  --include-ext cs,js,ts"

#do the work
# assumes that the current working dir is the repo dir
# all output goes to stdout
analyze() {
  echo "Date,Files,Lines,Blanks,Comments,Code,Complexity"
  period_date=$(git log --reverse --format=%cd --date=format:%Y-%m-%d | head -n 1 || true)
  period_epoch=$(date -j -f '%Y-%m-%d' "${period_date}" "+%s")
  current_epoch=$(date "+%s")


  MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
  # Iterate over each week from the first commit date to the present

  while [ "${period_epoch}" -le "${current_epoch}" ]; do
    # Checkout the repository to the state at the current date
    git checkout $(git rev-list -n 1 --before="${period_date} 23:59" "${MAIN_BRANCH}") > /dev/null 2>&1


    # Run scc and get the stats
    STATS=$($SCC_COMMAND )

    # just get summary, remove the row name, turn to CSV
    SUMMARY=$(echo "$STATS" | grep Total | sed 's/Total//' | sed -E 's/[[:space:]]+/,/g')


    # Increment the date by one week
    period_date=$(date -j -v+1w -f "%Y-%m-%d" "$period_date" "+%Y-%m-%d")
    echo $period_date$SUMMARY  $period_epoch $current_epoch $MAIN_BRANCH
    period_epoch=$(date -j -f '%Y-%m-%d' "${period_date}" "+%s")

  done
  git checkout "$MAIN_BRANCH"
}


( cd $REPO_PATH && analyze ) #> ${OUTPUT_FILE} )
