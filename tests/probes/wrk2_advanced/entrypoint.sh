#!/bin/bash

source $1

echo "Traffic generator configuration: "
echo -e "Logs: \t\t"$LogFile
echo -e "Schema: \t"$SCHEMA
echo -e "VNF External IP: \t"$EXTERNAL_IP
echo -e "Service Port: \t"$PORT
echo -e "Path: \t"$URL_PATH
echo -e "Connections: \t"$CONNECTIONS
echo -e "Duration: \t"$DURATION
echo -e "Threads: \t"$THREADS
echo -e "Header: \t"$HEADER
echo -e "Timeout: \t"$TIMEOUT
echo -e "Rate_array: \t\t"$RATES
echo -e "Proxy: \t\t"$PROXY

if [ -z $SCHEMA ] || [ -z $EXTERNAL_IP ] || [ -z $PORT ]; then
  echo "VNF Under Test endpoint was not set" > $LogFile
  exit 1
else
  opt1="$SCHEMA$EXTERNAL_IP:$PORT"
fi

if [ -z $URL_PATH ]; then
  opt1="$opt1/$URL_PATH"
fi

if [ -z $CONNECTIONS ]; then
  opt2="-connections 200"
else
  opt2="--connections $CONNECTIONS"
fi

if [ -z $DURATION ]; then
  opt3="--duration 300s"
else
  opt3="--duration $DURATION"
fi

if [ -z $THREADS ]; then
  opt4="--threads 5"
else
  opt4="--threads $THREADS"
fi

if [ -z $TIMEOUT ]; then
  opt5="--timeout 30s"
else
  opt5="--timeout $TIMEOUT"
fi

if [ ${#RATES[@]} -ne 0 ]; then
  opt6="10 20 50 100 500 1000"
else
  opt6="$RATES"
fi

if [ -z $HEADER ]; then
  opt7=""
else
  opt7="--header $HEADER"
fi

if [ "$PROXY" = "yes" ]; then
  config="/app/result_proxy.lua"
else
  config="/app/result.lua"
fi

for RATE in $RATES; do
  echo "COMMAND: /usr/local/bin/wrk -s $config $opt2 $opt3 $opt4 $opt5 --rate $RATE $opt7 --latency $opt1"
  /usr/local/bin/wrk -s $config $opt2 $opt3 $opt4 $opt5 --rate $RATE $opt7 --latency $opt1 > $RATE.tmp
  cat $RATE.tmp >>  $LogFile
  /bin/cat $RATE.tmp | tail -58 | jq '{requests, duration_in_microseconds, bytes, requests_per_sec, bytes_transfer_per_sec, latency_distribution}' > rate-$RATE.json
  /bin/cat $RATE.tmp | tail -58 | jq '{ graphs }' > graphs-$RATE.json
  /bin/cat $RATE.tmp | tail -58 | jq "{ requests_per_sec, \"requests\": $RATE }" > overall-$RATE.json
done

# Processing data

# Creating details.json file

let counter=0

# Obtain the json generated list
#requests=`ls rate*.json | tr "." "\n" | grep -v json | tr -d "rate-" | xargs`

jsondetail=`echo '{"details": [] }' | jq .`

for i in $RATES
do
  join_json=`cat rate-$i.json`
  let iteration=$counter+1
  jsondetail=`echo $jsondetail | jq ".details[$counter] +=  $join_json"`
  let counter++
done

jsondetail=`echo $jsondetail | jq [.]`

echo $jsondetail | jq . > details.json

# Creating graphs object

# Variables initialization
let counter=0

# Obtain the json generated list
#requests=`ls graphs*.json | tr "." "\n" | grep -v json | tr -d "graphs-" | xargs`

graphs=`echo '{"graphs": [] }' | jq .`

# Adding data to graphs object
for j in $RATES
do
  join_json=`cat graphs-$j.json | jq .graphs`
  graphs=`echo $graphs | jq ".graphs += $join_json"`
  let counter++
done

echo $graphs | jq .graphs > graphs.json
graphs=`echo $graphs | jq .graphs`

# Variables initialization
let counter=0

# Obtain the json generated list
#requests=`ls overall*.json | tr "." "\n" | sed 's/\overall-//g' | grep -v json | xargs`

# Graph template
#json=`echo '{"graphs": [ { "title": "Http Benchmark test", "x-axis-title": "Iteration", "x-axis-unit": "#", "y-axis-title": "Requests per second", "y-axis-unit": "rps", "type": "line", "series": { "s1": "requests_sent", "s2": "requests_processed" }, "data": { "s1": [], "s2": [] } }]} '`
json=`echo '{"graphs": [ { "title": "Http Benchmark test", "x-axis-title": "Iteration", "x-axis-unit": "#", "y-axis-title": "Requests per second", "y-axis-unit": "rps", "type": "line", "series": { "s1": "requests_sent", "s2": "requests_processed" }, "data": { "s1x": [], "s1y": [], "s2x": [], "s2y": [] } }]} '`

# Adding data to graphs object
for i in $RATES
do
  join_json=`cat overall-$i.json`
  let iteration=$counter+1
  s1=`echo $join_json | jq '.requests_per_sec'`
  s2=`echo $join_json | jq '.requests'`
  json=`echo $json | jq ".graphs[0].data.s1x += [$iteration]"`
  json=`echo $json | jq ".graphs[0].data.s1y += [$s1]"`
  json=`echo $json | jq ".graphs[0].data.s2x += [$iteration]"`
  json=`echo $json | jq ".graphs[0].data.s2y += [$s2]"`
#  json=`echo $json | jq ".graphs[0].data.s1[$counter] += { \"x-axis\": $iteration, \"y-axis\": $s1 }"`
#  json=`echo $json | jq ".graphs[0].data.s2[$counter] += { \"x-axis\": $iteration, \"y-axis\": $s2 }"`
  let counter++
done

echo $json | jq . > requests.json

final_graph_object=`echo $json | jq ".graphs += $graphs"`
the_graphs=`echo $final_graph_object | jq '.graphs'`
echo "the_graphs" $the_graphs

detail_json=`echo $jsondetail | jq ". += [$final_graph_object]"`
the_json=`echo $jsondetail | jq '.[].details'`
detail_sin=`echo $detail_json | jq "{ details: $the_json, graphs: $the_graphs}"`
#detail_sin=`echo $detail_json | jq "{ details: $jsondetail, graphs: $the_graphs}"`
#detail_sin=`jq "{ details: $jsondetail, graphs: $the_graphs}"`
echo  $detail_sin | jq . > $DataFile
echo "detail_sin" $detail_sin
