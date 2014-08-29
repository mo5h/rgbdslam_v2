#!/bin/bash
BASE_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd $BASE_DIRECTORY > /dev/null
PACKAGEDIR=`rospack find rgbdslam`/

if [[ "$1" == "" ]]; then 
  echo "This script will run rgbdslam on all bagfiles in this directory."
  echo "Usage: $0 <Directory for results>"
  TESTNAME=`date +%Y-%m-%d_%H:%M`
  echo "No directory given, using $TESTNAME."
  sleep 2
else
  TESTNAME=$1
fi

export ROS_MASTER_URI=http://localhost:11386
#roscore -p 11386&
#ROSCOREPID=$!
#echo Waiting for roscore
#sleep 3
for MAXFEATURES in 400 800 ; do
  for FEAT_TYPE in ORB; do 
    for CANDIDATES in 2 4 8; do
      for OBS_EVAL in  0.00; do
        for RANSAC_ITER in 250; do
          for DISTANCEMSR in GridAdjuster Adjuster Regular; do 
            if [[ $DISTANCEMSR == GridAdjuster ]]; then
              GRID_RESOLUTION=2
              ADJUSTER_ITERATION=20
              echo Using GridAdjuster $FEAT_TYPE Detector
            elif [[ $DISTANCEMSR == Adjuster ]]; then
              GRID_RESOLUTION=0
              ADJUSTER_ITERATION=20
              echo Using Adjuster $FEAT_TYPE Detector
            elif [[ $DISTANCEMSR == Regular ]]; then
              GRID_RESOLUTION=0
              ADJUSTER_ITERATION=0
              echo Using Regular $FEAT_TYPE Detector
            else 
              echo  ======================== ERROR: Invalid Value for variable DISTANCEMSR ========================
            fi
            for OPT_SKIP in 10; do #online/offline

              echo "Will evaluate RGBD-SLAM on the following bagfiles:"
              SELECTION=`ls rgbd*.bag`
              echo $SELECTION

              PARAM_DIRECTORY="$BASE_DIRECTORY/$TESTNAME/emm__$OBS_EVAL/CANDIDATES_$CANDIDATES/RANSAC_$RANSAC_ITER/HellingerDistance_$DISTANCEMSR/NN_0.5/OPT_SKIP_$OPT_SKIP/${FEAT_TYPE}/${MAXFEATURES}_Features/"
              for bagfile in $SELECTION; do
                BASE_NAME=`basename $bagfile .bag` 
                DIRECTORY="$PARAM_DIRECTORY/$BASE_NAME"
                LAUNCHFILE=`rospack find rgbdslam`/test/experiment_settings.launch

                mkdir -p $DIRECTORY
                if zgrep -q Coordinate $DIRECTORY/*estimate.txt.gz 2> /dev/null; then 
                  echo There are already results for $BASE_NAME in $DIRECTORY. Will skip this bagfile >&2
                  continue #don't overwrite existing results
                fi
                if grep -q Coordinate $DIRECTORY/*estimate.txt* 2> /dev/null; then 
                  echo There are already results for $BASE_NAME in $DIRECTORY. Will skip this bagfile >&2
                  continue #don't overwrite existing results
                fi
                #Remove old summary results if a new individual one is computed (will be recomputed further below)
                rm $PARAM_DIRECTORY/ate_evaluation_*.csv 2> /dev/null
                echo `date +%H:%M:%S` Results for $BASE_NAME are stored in `readlink -f $DIRECTORY`
                roslaunch rgbdslam `basename $LAUNCHFILE`  bagfile_name:=`readlink -f $bagfile` match_candidates:=$CANDIDATES sampled_candidates:=$CANDIDATES feature_type:=$FEAT_TYPE max_keypoints:=$MAXFEATURES ransac_iterations:=$RANSAC_ITER optimizer_skip_step:=$OPT_SKIP observability_threshold:=$OBS_EVAL adjuster_max_iterations:=$ADJUSTER_ITERATION detector_grid_resolution:=$GRID_RESOLUTION >  $DIRECTORY/logfile 2>&1
                #rosparam get /rgbdslam/config >>  $DIRECTORY/logfile 2>&1
                echo `date +%H:%M:%S` Finished processing $BASE_NAME

                #Move Result files, run evaluation routine
                mv ${bagfile}?* $DIRECTORY/
                cp ${BASE_NAME}-groundtruth.txt $DIRECTORY/
                cp $LAUNCHFILE $DIRECTORY/settings.xml #renamed to avoid name conflict with original file in roslaunch command
                #cp `readlink -f $0` $DIRECTORY/`basename $0`

                pushd $DIRECTORY > /dev/null
                test -e logfile.gz && mv logfile.gz logfile-failed.gz # retain one previous run
                gzip logfile
                popd > /dev/null
              done
              $PACKAGEDIR/rgbd_benchmark/summarize_evaluation.sh  $PARAM_DIRECTORY
              grep "absolute translational error.rmse" $PARAM_DIRECTORY >> $BASE_DIRECTORY/$TESTNAME/all_results.csv
            done
          done
        done
      done
    done
  done
done
echo "Generating Plots"
./figures.py $BASE_DIRECTORY/$TESTNAME/all_results.csv
echo "Compressing Raw Data"
tar czf $TESTNAME.tgz $BASE_DIRECTORY/$TESTNAME/emm*
echo "Removing Raw Data"
rm -rf $BASE_DIRECTORY/$TESTNAME/emm*

popd > /dev/null
