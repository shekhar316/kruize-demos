#!/bin/bash
#
# Copyright (c) 2022, 2022 Red Hat, IBM Corporation and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

current_dir="$(dirname "$0")"
source ${current_dir}/../common_helper.sh
source ${current_dir}/recommendations_demo/recommendation_helper.sh
# Default docker image repos
AUTOTUNE_DOCKER_REPO="docker.io/kruize/autotune_operator"

echo "${current_dir}/recommendations_demo/recommendation_helper.sh"

# Default cluster
CLUSTER_TYPE="openshift"

target="crc"
visualize=0

function usage() {
	echo "Usage: $0 [-s|-t] [-o kruize-image] [-r] [-c cluster-type] [-d] [--visualize]"
	echo "s = start (default), t = terminate"
	echo "r = restart kruize monitoring only"
	echo "o = kruize image. Default - docker.io/kruize/autotune_operator:<version as in pom.xml>"
	echo "c = supports minikube and openshift cluster-type"
	echo "d = duration of benchmark warmup/measurement cycles"
	echo "p = expose prometheus port"
	echo "visualize = Visualize the recommendations in grafana (Yet to be implemented)"
	exit 1
}

## Checks for the pre-requisites to run the monitoring demo
function prereq_check() {
	# Python is required only to run the monitoring experiment 
	python3 --version >/dev/null 2>/dev/null
	check_err "ERROR: python3 not installed. Required to start the demo. Check if all dependencies (python3,minikube) are installed."

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		minikube >/dev/null 2>/dev/null
		check_err "ERROR: minikube not installed."
		kubectl get pods >/dev/null 2>/dev/null
		check_err "ERROR: minikube not running. "
		## Check if prometheus is running for valid benchmark results.
		#prometheus_pod_running=$(kubectl get pods --all-namespaces | grep "prometheus-k8s-0")
		#if [ "${prometheus_pod_running}" == "" ]; then
		#	err_exit "Install prometheus for valid results from benchmark."
		#fi
	fi
}

###########################################
#   Kruize Install
###########################################
function kruize_install() {
	echo
	echo "#######################################"
	echo " Installing Kruize"
	if [ ! -d autotune ]; then
		echo "ERROR: autotune dir not found."
		if [ ${autotune_restart} -eq 1 ]; then
			echo "ERROR: Kruize not running. Wrong use of restart command"
		fi
		exit -1
	fi
	pushd autotune >/dev/null
		# Checkout the mvp_demo branch for now
		git checkout mvp_demo

		AUTOTUNE_VERSION="$(grep -A 1 "autotune" pom.xml | grep version | awk -F '>' '{ split($2, a, "<"); print a[1] }')"

		echo "Terminating existing installation of kruize with  ./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t"
		./deploy.sh -c ${CLUSTER_TYPE} -m ${target} -t
		sleep 5
		if [ -z "${AUTOTUNE_DOCKER_IMAGE}" ]; then
			AUTOTUNE_DOCKER_IMAGE=${AUTOTUNE_DOCKER_REPO}:${AUTOTUNE_VERSION}
		fi
		DOCKER_IMAGES="-i ${AUTOTUNE_DOCKER_IMAGE}"
		if [ ! -z "${HPO_DOCKER_IMAGE}" ]; then
			DOCKER_IMAGES="${DOCKER_IMAGES} -o ${AUTOTUNE_DOCKER_IMAGE}"
		fi
		echo
		echo "Starting kruize installation with  ./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}"
		echo

		if [ ${EXPERIMENT_START} -eq 0 ]; then
			CURR_DRIVER=$(minikube config get driver 2>/dev/null)
			if [ "${CURR_DRIVER}" == "docker" ]; then
				echo "Setting docker env"
			#	eval $(minikube docker-env)
			elif [ "${CURR_DRIVER}" == "podman" ]; then
				echo "Setting podman env"
			#	eval $(minikube podman-env)
			fi
		fi

		./deploy.sh -c ${CLUSTER_TYPE} ${DOCKER_IMAGES} -m ${target}
		#./deploy.sh -c minikube -i docker.io/kruize/autotune_operator:0.0.13_mvp -m crc
		check_err "ERROR: kruize failed to start, exiting"

		echo -n "Waiting 30 seconds for Autotune to sync with Prometheus..."
		sleep 30
		echo "done"
	popd >/dev/null
	echo "#######################################"
	echo
}

function monitoring_demo_start() {

	#minikube >/dev/null
	#check_err "ERROR: minikube not installed"
	# Start all the installs
	start_time=$(get_date)
	echo
	echo "#######################################"
	echo "#           Demo Setup                #"
	echo "#######################################"
	echo
	echo "--> Clone Required Repos"

	if [ ${CLUSTER_TYPE} == "minikube" ]; then
		echo "--> Setup minikube"
		echo "--> Installs Prometheus"
	fi

	echo "--> Installs Kruize"
	echo "--> Creates experiments in monitoring mode"
	echo "--> Updates the results into Kruize"
	echo "--> Fetches the recommendations from Kruize"
	echo

	if [ ${monitoring_restart} -eq 0 ]; then
		clone_repos autotune

		if [ ${CLUSTER_TYPE} == "minikube" ]; then
	#		echo "Starting minikube"		
	#		minikube_start
			if [[ ${monitorRecommendations} == 1 ]]; then
				## Check if prometheus is running for valid benchmark results.
		                prometheus_pod_running=$(kubectl get pods --all-namespaces | grep "prometheus-k8s-0")
                		if [ "${prometheus_pod_running}" == "" ]; then
					echo "Calling prometheus_install"
					prometheus_install
					echo "Calling prometheus_install done"
				fi
			fi
		fi

	fi

	# Check for pre-requisites to run the demo
	python3 -m pip install --user -r requirements.txt >/dev/null 2>&1
	prereq_check ${CLUSTER_TYPE}

	kruize_install

	# Deploy benchmarks. Create an experiment, update results and fetch recommendations using Kruize REST APIs
	if [[ ${dataDrivenRecommendations} -eq 1 ]]; then
		echo "#######################################"
		# crc mode considers the individual data. Else, it considers the aggregated data.
		if [[ ${mode} == "crc" ]]; then
			echo "Running the recommendation Infra demo with the existing data in crc mode..."
			monitoring_recommendations_demo_with_data ${resultsDir} crc
		else
			echo "Running the recommendation Infra demo with the existing data..."
			monitoring_recommendations_demo_with_data ${resultsDir}
		fi
		echo
		echo "Completed"
		echo "#######################################"
		echo ""
		echo "Use recommendationsOutput.csv to generate visualizations for the generated recommendations."
	elif [[ ${monitorRecommendations} -eq 1 ]]; then
		#if [ -z $k8ObjectType ] && [ -z $k8ObjectName ]; then
		if [[ ${demoBenchmark} -eq 1 ]]; then
			echo "Running the monitoring mode  with demo benchmark"
                        monitoring_recommendations_demo_with_benchmark
		else
			echo "Running the monitoring mode on a cluster"
			monitoring_recommendations_demo_for_k8object
		fi
	elif [[ ${compareRecommendations} -eq 1 ]]; then
                comparing_recommendations_demo_with_data ./recommendations_demo/tfb-results/splitfiles
	fi


	echo
	end_time=$(get_date)
	elapsed_time=$(time_diff "${start_time}" "${end_time}")
	echo "Success! Recommendations Infra demo set-up took ${elapsed_time} seconds"
	echo
	if [ ${prometheus} -eq 1 ]; then
		expose_prometheus
	fi
	
}

function monitoring_demo_terminate() {
	echo
	echo "#######################################"
	echo "#     Monitoring Demo Terminate       #"
	echo "#######################################"
	echo
	pushd autotune >/dev/null
		./deploy.sh -t -c ${CLUSTER_TYPE}
		echo "ERROR: Failed to terminate kruize monitoring"
		echo
	popd >/dev/null
}


function monitoring_demo_cleanup() {
	echo
	echo "#######################################"
	echo "#    Monitoring Demo setup cleanup    #"
	echo "#######################################"
	echo

	delete_repos autotune

	if [ ${visualize} -eq 1 ]; then
		delete_repos pronosana
	fi

#	if [ ${CLUSTER_TYPE} == "minikube" ]; then
#		minikube_delete
#	fi
	
	echo "Success! Monitoring Demo setup cleanup completed."
	echo
}

# By default we start the demo & experiment and we dont expose prometheus port
prometheus=0
monitoring_restart=0
start_demo=1
EXPERIMENT_START=0
# Iterate through the commandline options
while getopts o:c:d:prst-: gopts
do

	 case ${gopts} in
         -)
                case "${OPTARG}" in
                        visualize)
                                visualize=1
				;;
			dataDrivenRecommendations)
				dataDrivenRecommendations=1
				;;
			monitorRecommendations)
				monitorRecommendations=1
                                ;;
			compareRecommendations)
				compareRecommendations=1
				;;
			demoBenchmark)
				demoBenchmark=1
				;;
			k8ObjectName=*)
				k8ObjectName=${OPTARG#*=}
				;;
			k8ObjectType=*)
				k8ObjectType=${OPTARG#*=}
				;;
			mode=*)
				mode=${OPTARG#*=}
				;;
			dataDir=*)
				resultsDir=${OPTARG#*=}
				;;
			clusterName=*)
				CLUSTER_NAME=${OPTARG#*=}
				;;

                        *)
                esac
                ;;

	o)
		AUTOTUNE_DOCKER_IMAGE="${OPTARG}"
		;;
	p)
		prometheus=1
		;;
	r)
		monitoring_restart=1
		;;
	s)
		start_demo=1
		;;
	t)
		start_demo=0
		;;
	c)
		CLUSTER_TYPE="${OPTARG}"
		;;
	d)
		DURATION="${OPTARG}"
		;;
	*)
			usage
	esac
done

#Todo
# Options
# Generate recommendations for the data given.

# Monitor the metrics in a cluster to generate recommendations

# Benchmark specific recommendations

# Copy the previous recommendationsOutput.csv and experimentOutput.csv into another for future purpose.
if [ -e "recommendationsOutput.csv" ]; then
	mv recommendationsOutput.csv recommendationsOutput-$(date +%Y%m%d).csv
fi
if [ -e "experimentOutput.csv" ]; then
        mv experimentOutput.csv experimentOutput-$(date +%Y%m%d).csv
fi

if [ ${start_demo} -eq 1 ]; then
	monitoring_demo_start
else
	monitoring_demo_terminate
	monitoring_demo_cleanup
fi
