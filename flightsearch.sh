#!/bin/bash
source "secret"

help()
{
 echo "Options :"
 echo "-h           - help "
 echo "-v           - version "
 echo "-a           - sends saved alert request, and display notification in case of price change"
}

f_alert_request()
{
RESPONSE=`mktemp`
source "./alert"
curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares?apikey=$KEY&departureAirportIataCode=$FROM&arrivalAirportIataCode=$TO&outboundDepartureDateFrom=$GODATE&outboundDepartureDateTo=$GODATE&inboundDepartureDateFrom=$BACKDATE&inboundDepartureDateTo=$BACKDATE&currency=PLN" > $RESPONSE

    readarray -t OUT_PRICE < <(cat $RESPONSE | jq -r ".fares[].outbound | .price.value")
    readarray -t IN_PRICE < <(cat $RESPONSE | jq -r ".fares[].inbound | .price.value")

    if [ $OUT_PRICE != $OLD_OUT_PRICE  ] || [ $IN_PRICE != $OLD_IN_PRICE  ]; then
    zenity zenity --notification  --text="Price $FROM -> $TO has changed.\n Now its $FROM -> $OUT_PRICE zł. and $FROM <- $IN_PRICE zł."
    fi
}

while getopts hva CHOICE 2>/dev/null ; do
	case $CHOICE in
	    a) f_alert_request
	       exit;;
	    h) help
	       exit;;
	    v) cat ./header
	       exit;;
	    ?) echo "Wrong option, write -h for help."
	       exit;;
	esac
    done

###intro


f_collect_resources() {
    if [ ! -f ./routes.json ]; then
        curl http://apigateway.ryanair.com/pub/v1/core/3/routes?apikey=$KEY   > routes.json
    fi
    if [ ! -f ./airports.json ]; then
        curl http://apigateway.ryanair.com/pub/v1/core/3/airports?apikey=$KEY > airports.json
    fi
    if [ ! -f ./countries.json ]; then
        curl http://apigateway.ryanair.com/pub/v1/core/3/countries?apikey=$KEY > countries.json
    fi
    if [ ! -f ./cities.json ]; then
        curl http://apigateway.ryanair.com/pub/v1/core/3/cities?apikey=$KEY > cities.json
    fi

    readarray -t COUNTRIES_NAME < <(cat countries.json | jq -r '.[] | .name')
    readarray -t COUNTREIS_CODE < <(cat countries.json | jq -r '.[] | .code')
}


f_askfrom(){
    RESPONSE=`zenity --list --column "country" --title "From" --text "Pick country" "${COUNTRIES_NAME[@]}"`
    for (( i=0; $i <= ${#COUNTRIES_NAME[@]}; i++ )); do
        if [[ ${COUNTRIES_NAME[i]} == $RESPONSE ]];then
            CTRCODE=${COUNTREIS_CODE[i]}
            break;
        fi
    done
     if [[ -z $RESPONSE ]] ; then
       exit
    fi
    readarray -t CITIES_NAME < <(cat ./cities.json | jq -r ".[] | select(.countryCode==\"$CTRCODE\") | .code")

    if [[ ${#CITIES_NAME[@]} > 1 ]]; then
        RESPONSE=`zenity --list --column "city" --title "From" --text "Pick city" "${CITIES_NAME[@]}"`
    else
        RESPONSE=$CITIES_NAME
        zenity --info --text "You will fly from ${CITIES_NAME[0]}"
    fi

    readarray -t AIRPORTS_NAME < <(cat ./airports.json | jq -r ".[] | select(.cityCode==\"$RESPONSE\") | .name")
    readarray -t AIRPORTS_IATA < <(cat ./airports.json | jq -r ".[] | select(.cityCode==\"$RESPONSE\") | .iataCode")


    if [[ ${#AIRPORTS_NAME[@]} > 1 ]]; then
        RESPONSE=`zenity --list --column "airport" --title "From" --text "Airport" "${AIRPORTS_NAME[@]}"`
        for (( i=0; $i <= ${#AIRPORTS_NAME[@]}; i++ )); do
            if [[ ${AIRPORTS_NAME[i]} == $RESPONSE ]];then
                RESPONSE=${AIRPORTS_IATA[i]}
                break;
            fi
        done
    else
        RESPONSE=${AIRPORTS_IATA[0]}
    fi
    FROM=$RESPONSE
}
#result in $FROM

f_askdir(){
    if [[ -z $FROM ]] ; then
       exit
    fi
    readarray -t AIRPORTS_IATA < <(curl "http://apigateway.ryanair.com/pub/v1/core/3/routes/$FROM/iataCodes?apikey=$KEY" | jq -r ".[] | .")
    unset $AIRPORTS_NAME
    for (( i=0 ,j=0; $i < ${#AIRPORTS_IATA[@]}; i++ ,j++ )); do
        AIRPORTS_NAME[$j]=`cat ./airports.json | jq -r ".[] | select(.iataCode==\"${AIRPORTS_IATA[$i]}\") | .name"`
        if [[ -z ${AIRPORTS_NAME[$j]} ]]; then
            j=$j-1                                                                               #czasami przychodzi iataCode którego nie ma na liście lotnisk;/ Dzieki ryanair
        fi
    done
    if [[ ${#AIRPORTS_NAME[@]} > 1 ]]; then
        TO=`zenity --list --title "To" --column "Name" --text "Pick airport:" "ANY" "${AIRPORTS_NAME[@]}"`
    else
        TO=${AIRPORTS_NAME[0]}
        zenity --info --text "The only direction you can fly is $TO"
    fi

    if [ $TO != "ANY" ]; then
        TO=`cat ./airports.json | jq -r ".[] | select(.name==\"$TO\") | .iataCode"`
    fi
}
#RESUlT IN $TO. Use func always after f_askfrom

f_calendarform()
{
    if [[ -z $TO  ]] ; then
       exit
    fi
    GODATE=`zenity --forms --title="Input your flight date" --text="Your flight date" \
    --add-calendar="Departure date"`\
    GODATE=`echo $GODATE | sed -r  's/([0-9]{2})\.([0-9]{2})\.([0-9]{4})/\3-\2-\1/g'`

    if [[ -z $GODATE  ]] ; then
       exit
    fi

    BACKDATE=`zenity --forms --title="Input your flight date" --text="Your flight date" \
    --add-calendar="Arrival date"`\
    BACKDATE=`echo $BACKDATE | sed -r  's/([0-9]{2})\.([0-9]{2})\.([0-9]{4})/\3-\2-\1/g'`

    if [[ -z $BACKDATE  ]] ; then
       exit
    fi

    if [ $TO != "ANY" ];then
        TOLERANCY=`zenity --list  --radiolist --column 'Select...' --column  'How close to date' FALSE 'Exactly' FALSE 'Week' FALSE 'Month'`
    fi
}
#Result in $GODATE ,$BACKDATE and $TOLERANCY


f_present_exactly_result()
{

    readarray -t WHERE < <(cat $RESPONSE | jq -r ".fares[].outbound | .arrivalAirport.name")
    readarray -t OUT_DAY < <(cat $RESPONSE | jq -r ".fares[].outbound | .departureDate")
    readarray -t OUT_PRICE < <(cat $RESPONSE | jq -r ".fares[].outbound | .price.value")
    readarray -t IN_DAY < <(cat $RESPONSE | jq -r ".fares[].inbound | .departureDate")
    readarray -t IN_PRICE < <(cat $RESPONSE | jq -r ".fares[].inbound | .price.value")

    for (( i=0; $i < ${#OUT_PRICE[@]}; i++ )); do
        echo "<h1> ${WHERE[$i]} </h1>" >> $SEARCH
        echo "-> ${OUT_DAY[$i]} ${OUT_PRICE[$i]} zł <br/>" >>$SEARCH
        echo "<- ${IN_DAY[$i]} ${IN_PRICE[$i]} zł <br/>" >>$SEARCH
    done
    zenity --text-info --html --height=400 --width=700  --filename=$SEARCH
}

f_present_result()
{
    readarray -t OUT_PRICES_PLN < <(cat $RESPONSE | jq -r ".outbound.fares[] | select(.unavailable==false) | .price.value")
    readarray -t OUT_DAY< <(cat $RESPONSE  | jq -r ".outbound.fares[] | select(.unavailable==false) | .day")
    readarray -t IN_PRICES_PLN < <(cat $RESPONSE  | jq -r ".inbound.fares[] | select(.unavailable==false) | .price.value")
    readarray -t IN_DAY< <(cat $RESPONSE  | jq -r ".inbound.fares[] | select(.unavailable==false) | .day")

    echo "<h1>$FROM -> $TO</h1>" >> $SEARCH
    for (( i=0; $i < ${#OUT_PRICES_PLN[@]}; i++ )); do
        echo "${OUT_DAY[$i]} ${OUT_PRICES_PLN[$i]} zł <br/>" >> $SEARCH
    done
    echo "<h1>$TO -> $FROM </h1>" >> $SEARCH
    for (( i=0; $i < ${#IN_PRICES_PLN[@]}; i++ )); do
        echo "${IN_DAY[$i]}  ${IN_PRICES_PLN[$i]} zł <br/> " >> $SEARCH
    done
    zenity --text-info --html --height=400 --width=700 --filename=$SEARCH
}


f_search()
{
RESPONSE=`mktemp`
SEARCH=`mktemp`

if [ $TO == "ANY" ]; then
    curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares?apikey=$KEY&departureAirportIataCode=$FROM&outboundDepartureDateFrom=$GODATE&outboundDepartureDateTo=$GODATE&inboundDepartureDateFrom=$BACKDATE&inboundDepartureDateTo=$BACKDATE&currency=PLN" > $RESPONSE
    f_present_exactly_result
elif [ $TOLERANCY == "Exactly" ]; then
    curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares?apikey=$KEY&departureAirportIataCode=$FROM&arrivalAirportIataCode=$TO&outboundDepartureDateFrom=$GODATE&outboundDepartureDateTo=$GODATE&inboundDepartureDateFrom=$BACKDATE&inboundDepartureDateTo=$BACKDATE&currency=PLN" > $RESPONSE
    f_present_exactly_result
    f_create_alert
else
    curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares/$FROM/$TO/cheapestPerDay?apikey=$KEY&currency=PLN&outbound${TOLERANCY}OfDate=$GODATE&inbound${TOLERANCY}OfDate=$BACKDATE"  > $RESPONSE
    f_present_result
fi
}

f_create_alert()
{
`zenity --question --text="Would you like to create price alert for this flight?"`
if [ $? == 1 ]; then
return
fi

echo 'FROM''='$FROM > "./alert"
echo 'TO''='$TO >> "./alert"
echo 'GODATE''='$GODATE >> "./alert"
echo 'BACKDATE''='$BACKDATE >> "./alert"
echo 'OLD_OUT_PRICE''='$OUT_PRICE >> "./alert"
echo 'OLD_IN_PRICE''='$IN_PRICE >> "./alert"

(crontab -l 2>/dev/null; echo "11 12,15,18 * * * $(pwd)$0 -a") | crontab -
}

f_main()
{
    f_collect_resources
    f_askfrom
    f_askdir
    f_calendarform
    f_search
}

f_main
