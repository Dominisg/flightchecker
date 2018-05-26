#!/bin/bash
source "secret"

#collecting resources

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

    echo ${CITIES_NAME[@]}

    if [[ ${#CITIES_NAME[@]} > 1 ]]; then
        RESPONSE=`zenity --list --column "city" --title "From" --text "Pick city" "${CITIES_NAME[@]}"`
    else
        RESPONSE=$CITIES_NAME
        zenity --info --text "You will fly from ${CITIES_NAME[0]}"
    fi

    readarray -t AIRPORTS_NAME < <(cat ./airports.json | jq -r ".[] | select(.cityCode==\"$RESPONSE\") | .name")
    readarray -t AIRPORTS_IATA < <(cat ./airports.json | jq -r ".[] | select(.cityCode==\"$RESPONSE\") | .iataCode")


    if [[ ${#AIRPORTS_NAME[@]} > 1 ]]; then
        RESPONSE=`zenity --entry --title "From" --text "Airport" "${AIRPORTS_NAME[@]}"`
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
    curl "http://apigateway.ryanair.com/pub/v1/core/3/routes/$FROM/iataCodes?apikey=$KEY"
    unset $AIRPORTS_NAME
    for (( i=0 ,j=0; $i < ${#AIRPORTS_IATA[@]}; i++ ,j++ )); do
        AIRPORTS_NAME[$j]=`cat ./airports.json | jq -r ".[] | select(.iataCode==\"${AIRPORTS_IATA[$i]}\") | .name"`
        if [[ -z ${AIRPORTS_NAME[$j]} ]]; then
            j=$j-1                                                                               #czasami przychodzi iataCode którego nie ma na liście lotnisk;/ Dzieki ryanair
        fi
    done
    echo $AIRPORTS_NAME
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
    BACKDATE=`zenity --forms --title="Input your flight date" --text="Your flight date" \
    --add-calendar="Arrival date"`\
    BACKDATE=`echo $BACKDATE | sed -r  's/([0-9]{2})\.([0-9]{2})\.([0-9]{4})/\3-\2-\1/g'`
    if [ $TO != "ANY" ];then
     TOLERANCY=`zenity --list  --radiolist --column 'Select...' --column  'How close to date' FALSE 'Exactly' FALSE 'Week' FALSE 'Month'`
    fi
}
#Result in $GODATE ,$BACKDATE and $TOLERANCY

f_search()
{
RESPONSE=`mktemp`

RESPONSE="odpowiedz2.json"
if [ $TO == "ANY" ]; then
    curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares?apikey=$KEY&departureAirportIataCode=$FROM&outboundDepartureDateFrom=$GODATE&outboundDepartureDateTo=$GODATE&inboundDepartureDateFrom=$BACKDATE&inboundDepartureDateTo=$BACKDATE&currency=PLN" > $RESPONSE
elif [ $TOLERANCY == "Exactly" ]; then
    curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares?apikey=$KEY&departureAirportIataCode=$FROM&arrivalAirportIataCode=$TO&outboundDepartureDateFrom=$GODATE&outboundDepartureDateTo=$GODATE&inboundDepartureDateFrom=$BACKDATE&inboundDepartureDateTo=$BACKDATE&currency=PLN"  > $RESPONSE
else
    curl -X GET "http://apigateway.ryanair.com/pub/v1/farefinder/3/roundTripFares/$FROM/$TO/cheapestPerDay?apikey=$KEY&currency=PLN&outbound${TOLERANCY}OfDate=$GODATE&inbound${TOLERANCY}OfDate=$BACKDATE"  > $RESPONSE
fi



}



f_collect_resources
f_askfrom
f_askdir
f_calendarform
f_search
echo $DATE











