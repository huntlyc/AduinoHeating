/* Copyright 2010 Huntly Cameron <huntly [dot] cameron [at] gmail [dot] com>
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#include <SPI.h>
#include <Ethernet.h>
#include <OneWire.h>

//Set up networking.
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 172,16,11, 220 };
byte gateway[] = { 172,16,11, 1 };
byte subnet[] = { 255, 255, 255, 0 };
Server server(80);

//Season
String CURRENT_SEASON = "winter";

//Temp Offsets
const double UPPER_OFFSET = 0.25;
const double LOWER_OFFSET = 0.5;

//Sensor id's
const int SCOTT = 1;
const int HUNTLY = 2;
const int OFFICE = 3;
const int HALL = 4;
const int BATHROOM = 5;
const int KITCHEN = 6;
const int LIVINGROOM = 7;
const int OUTSIDE = 8;


boolean isBoilerOn = false;

//One Wire Set up
OneWire ds(6);  // on pin 10
const int ADDRESS_SIZE = 8;
//structs
typedef struct sensor
{
  int id;
  byte sensorId[8]; //address of sensor
  String name; //room name
  double curTemp;  //temperature its currently at
  double prevTemp; //previous recorded temperature
  double winterOffset;
  double summerOffset;
  int setTemp; //target temperature
  boolean isZoneValveOpen; //room zone valve
  int ledPin; //ledpin id for wall mount
} sensor;

//Wrapper for list of sensor structs.
struct sensorList
{
  sensor list[8];  
  int size;
};

struct sensorList _gList;

void alterBoilerState();
void checkZoneTemps();
String convertToString(double num);
String constructXML();
void parseValues(String, struct sensorList *);
void setNewTemps(String);
void updateCurrentTempValues();



//********************************  USER DEFINED METHODS***********************//

//Function: alterBoilerState()
//Returns: void
//Description:  Loops through all the sensors, checks to see if
//              a zone valve is open, if so turn the boiler on.
//              If no valves are open, shut the boiler off.
void alterBoilerState()
{
  boolean valveOpen = false;
  for (int i = 0; i < _gList.size; i++)
  {
    if(_gList.list[i].isZoneValveOpen)
    {
      valveOpen = true;                
    }
  }

  if (valveOpen && !(isBoilerOn))
  {
    Serial.println("Firing Boiler");
    //Fire Boiler
    Serial1.println("N8");
    isBoilerOn = true;
  }
  else if (!(valveOpen) && isBoilerOn)
  {
    Serial.println("Shutting down boiler");
    //Shut off Boiler
    Serial1.println("F8");
    isBoilerOn = false;
  }
}

//Function: turnONLED
//params: int - pinNumber on the arduino for the LED
//return: void
//Description: see function name ;)
void turnOnLED(int pinNumber)
{
    digitalWrite(pinNumber, HIGH);  
}

//Function: turnOffLED
//params: int - pinNumber on the arduino for the LED
//return: void
//Description: see function name ;)
void turnOffLED(int pinNumber)
{
    digitalWrite(pinNumber, LOW);  
}

//Function: openZoneValve
//Params: int - position in _gList array
//Return: void
//Description: switches relay on
void openZoneValve(int listPosition)
{
  Serial1.print("N");
  Serial1.println(_gList.list[listPosition].id);
  _gList.list[listPosition].isZoneValveOpen = true;
}

//Function: closeZoneValve
//Params: int - position in _gList array
//Return: void
//Description: switches relay off
void closeZoneValve(int listPosition)
{
  Serial1.print("F");
  Serial1.println(_gList.list[listPosition].id);
  _gList.list[listPosition].isZoneValveOpen = false;
}

//Function: checkZoneTemps()
//Params: nons
//Return: void
//Description: Will run though the sensor list and check the set temp
//             against the current temp and alter the zone valves
//             accordingly.
void checkZoneTemps()
{
  updateCurrentTempValues();//refresh the temps
  
  for (int i = 0; i < _gList.size; i++)
  {

    //We don't want to heat the outside world or bathroom or kitchen, yet.
    if (_gList.list[i].id != OUTSIDE || _gList.list[i].id != BATHROOM ||  _gList.list[i].id != KITCHEN) 
    {
      //If too hot, shut off zone valve and LED.
      //else if too cold, turn on zone valve and put on led.
      if ((_gList.list[i].curTemp > (_gList.list[i].setTemp + UPPER_OFFSET)) && 
          (_gList.list[i].isZoneValveOpen)) 
      {        
        closeZoneValve(i);
        turnOffLED(_gList.list[i].ledPin);
      }
      else if ((_gList.list[i].curTemp < (_gList.list[i].setTemp - LOWER_OFFSET)) && 
               (_gList.list[i].isZoneValveOpen == false)) //Too cold, open zone valve & turn on led
      {
        openZoneValve(i);
        turnOnLED(_gList.list[i].ledPin);        
      }
    }
  }
  
  alterBoilerState();
}

//Function: convertToString(double)
//Param: double - number to convert
//Return: String - string representation of the double param
//Description:  Will turn a passed in double into a string,
//              no sanity checking though...
String convertToString(double num)
{
  String returnVal = "";
  int whole;
  int fract;
  int tmp;

  //Split double into component parts
  tmp = num*100;
  whole = tmp / 100;  
  fract = tmp % 100;
  
  //package as string
  returnVal += whole;
  returnVal += ".";
  returnVal += fract;
  
  return (returnVal);
}

//Function: constructHTML()
//Params: none
//Return: String - Containing the raw XML code to be spat out
//        to the client.
String constructXML()
{
  String XML = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";
  XML += "<sensors>";
  sensor s;
  for (int i = 0; i < _gList.size; i++)
  {
    s = _gList.list[i];
    
    //Write Sensor ID
    XML += "<sensor> <id>";
    XML += s.id;
    XML +="</id>";
    
    //Write Name
    XML += "<name>";
    XML += s.name;
    XML += "</name>";
    
    //Write prev temp
    XML += "<previous>";
    XML += convertToString(s.prevTemp);
    XML += "</previous>";
    
    //Write cur temp
    XML += "<current>";
    XML += convertToString(s.curTemp);
    XML += "</current>";
    
    //Write set temp
    XML += "<set>";
    XML += s.setTemp;
    XML += "</set>";
    XML += "</sensor>";
  }
  
  XML += "</sensors>";
  
  return (XML);
  
}



//Function: parseSetTempValues()
//Params: String paramList - String of params: id=4&val=20&id=10&val=20 and so on.
//        struct sensorList* - Pointer to a sensorList struct which willbe populated (pass by-reference)
//Returns: void
//Description: Takes ID's and Values out of request string and populates
//             sensorList struc with these values.
void parseSetTempValues(String qList, struct sensorList *myList)
{
  int arraySize = 0;
  int startPoint = 0;
  int endPoint = 0;
  boolean foundEndOfList = false;
  String tmpStr;
  char value[3];
  
  
  //parse out the id's and values
  do
  {
    //If we've still got a param
    if(qList.indexOf('=', endPoint) != -1)
    {
      sensor s1; //create a new sensor struct


      /**
       * NOTE!!  There is no sanity checking on the paramlist,
       *         I'm assuming that its id, value, id, value e.t.c
       *         For your own implementation needs, you might want to
       *         alter this.... Especially if its internet facing!
       */
      //get id
      startPoint = qList.indexOf('=', endPoint) + 1;
      endPoint = qList.indexOf('&', startPoint);
      

      tmpStr =  qList.substring(startPoint, endPoint);
      tmpStr.toCharArray(value, sizeof(tmpStr));
      
      //NOTE!  I'm blindly assuming that the id value is in fact an integer!
      s1.id = atoi(value);
      
      //get val
      startPoint = qList.indexOf('=', endPoint) + 1;
      endPoint = qList.indexOf('&', startPoint);

      tmpStr =  qList.substring(startPoint, endPoint);
      tmpStr.toCharArray(value, sizeof(tmpStr));
      
      //NOTE!  Again, I'm blindly assuming that the value is in fact an integer!
      s1.setTemp = atoi(value);      
      (*myList).list[arraySize] = s1;

      arraySize++; //bump up the array size

    }
    else
    {
      foundEndOfList = true;
    }          
  }
  while (foundEndOfList == false);  
  
  //Set list size
  (*myList).size = arraySize;
}

//Function: setNewTemps(String)
//Paramms: String requestString - HTTP GET request string like-> ?id=4&val=2&id=23&val=3
//Return: void
//Description:  Will take a set of id's and temp values and if the temp values differ then they will
//              be set.
void setNewTemps(String requestString)
{
  String qList; //query list (params)
  struct sensorList sList; //list of sensor structs  
  
  //Get the param list
  qList = requestString.substring(requestString.indexOf('?') +1 , requestString.indexOf(' ', requestString.indexOf('/')));
    
  //Fill up a temp list of sensors with the details from the request
  parseSetTempValues(qList, &sList);

  //For each element in the temp list
  for(int i = 0; i < sList.size; i++)
  {
    //Scan the _gList for the current ID    
    for(int j = 0; j < _gList.size; j++)
    {  
      //If the ID is valid and the value is different, then write the new value.
      if((sList.list[i].id == _gList.list[j].id))
      {
        _gList.list[j].setTemp = sList.list[i].setTemp;            
      }          
    }
  }        
}  

void updateSeason(String requestString)
{
  String qList; //query list (params)
  int startPoint = 0;
  int endPoint = 0;
  boolean foundEndOfList = false;
  String season;
  
  //Get the param list
  qList = requestString.substring(requestString.indexOf('?') +1 , requestString.indexOf(' ', requestString.indexOf('/')));
  
  /**
   * NOTE!!  There is no sanity checking on the paramlist,
   *         I'm assuming that its 'season=winter' or 'season=summer'
   *         For your own implementation needs, you might want to
   *         alter this.... Especially if its internet facing!
  */
  startPoint = qList.indexOf('=', endPoint) + 1;
  endPoint = qList.indexOf('&', startPoint);
      
  season =  qList.substring(startPoint, endPoint);
  
  CURRENT_SEASON = season;
}

//Function: updateCurrentTempValues()
//Params: none
//Return: void
//Description:  Polls the One-wire temp sensors and
//              updates the sensor list with the new
//              values
void updateCurrentTempValues()
{
  int HighByte, LowByte, TReading, SignBit, Tc_100, Fract;
  double TReadingd;
  boolean isValidAddr = false;
  double curTemp;

  for (int count = 0; count < 8; count++)
  {
    byte i;
    byte present = 0;
    byte data[12];
    byte addr[8];
    int id = 0;

    if ( !ds.search(addr)) {
        ds.reset_search();
        return;
    }
    
    for(int i = 0; i < _gList.size; i++)
    {      
      if(memcmp(addr, _gList.list[i].sensorId, ADDRESS_SIZE) == 0)
      {                
        isValidAddr = true;    
        id = _gList.list[i].id;        
      }      
    }
    
    if(isValidAddr)
    {
      if ( OneWire::crc8( addr, 7) != addr[7] ||  addr[0] != 0x28)
      {
          //either wrong address or failed a CRC check, bail out
          return;
      }

      ds.reset();
      ds.select(addr);
      ds.write(0x44); // start conversion, with *NO* parasite power
      present = ds.reset();
      ds.select(addr);    
      ds.write(0xBE);         // Read Scratchpad

      for ( i = 0; i < 9; i++)// we need 9 bytes
      {          
        data[i] = ds.read();
      }
  
      LowByte = data[0];
      HighByte = data[1];
      TReadingd = (HighByte << 8) + LowByte;
      SignBit = TReading & 0x8000;  // test most sig bit
  
      if (SignBit) // negative
      {
        TReadingd *= -1.0;
      }

      curTemp = ((6 * TReadingd) + TReadingd / 4) / 100 ;    // multiply by (100 * 0.0625) or 6.25

      //Due to sensors being close to walls, windows etc.  We've calculated
      //offsets which should be applied to read the true temperature.
      if(CURRENT_SEASON.compareTo("winter") == 0)
      {
        curTemp  -= _gList.list[i].winterOffset;
      }
      else if(CURRENT_SEASON.compareTo("summer") == 0)
      {
        curTemp  -= _gList.list[i].summerOffset;        
      }
      
      for(int i = 0; i < _gList.size; i++)
      {
        if (id == _gList.list[i].id)
        {
          _gList.list[i].prevTemp = _gList.list[i].curTemp;
          _gList.list[i].curTemp = curTemp;          
        }
      }
    }
    isValidAddr = false; //reset for next itter
  }
}

//***************************** ARDUINO METHODS ***************************//
void setup()
{
    // initialize the Ethernet device
    Ethernet.begin(mac, ip, gateway, subnet);
    // start listening for clients
    server.begin();
    // open the serial port
    Serial.begin(9600);
    Serial1.begin(9600); //Serial 1 for the relay board
    pinMode(13, OUTPUT);
 
    //Assign stack space and populate structs
    struct sensor scott, huntly, office, hallway, bathroom, kitchen, livingroom, outside;

    scott.id = 1;
    byte tmp1[] = {0x28, 0x95, 0x6E, 0xBB, 0x02, 0x00, 0x00, 0xBD};
    memcpy(scott.sensorId, tmp1, 8);
    scott.name = "Scott";
    scott.prevTemp = 20;  
    scott.winterOffset = 0;
    scott.summerOffset = 0;
    scott.setTemp = 5;
    scott.isZoneValveOpen = false;
    scott.ledPin = 31;
    _gList.list[0] = scott;
  
  
    huntly.id = 2;
    huntly.name = "Huntly";
    byte tmp2[] = {0x28, 0x2A, 0x82, 0xBB, 0x02, 0x00, 0x00, 0x65};
    memcpy(huntly.sensorId, tmp2, 8);
    huntly.prevTemp = 20;
    huntly.winterOffset = 0;
    huntly.summerOffset = 0;
    huntly.setTemp = 5;  
    huntly.isZoneValveOpen = false;  
    huntly.ledPin = 32;
    _gList.list[1] = huntly;
  
    office.id = 3;
    byte tmp3[] = {0x28, 0x1F, 0x84, 0xBB, 0x02, 0x00, 0x00, 0xFF};
    memcpy(office.sensorId, tmp3, 8);
    office.name = "The Office";
    office.prevTemp = 20;
    office.winterOffset = -2.46;
    office.summerOffset = 0;    
    office.setTemp = 5;  
    office.isZoneValveOpen = false;  
    office.ledPin = 33;    
    _gList.list[2] = office;  
  
    hallway.id = 4;
    byte tmp4[] = {0x28, 0x1F, 0x84, 0xBB, 0x2, 0x0, 0x0, 0x0};
    memcpy(hallway.sensorId, tmp4, 8);
    hallway.name = "Hallway";
    hallway.prevTemp = 20;
    hallway.winterOffset = 0;
    hallway.summerOffset = 0;
    hallway.setTemp = 5;
    hallway.curTemp = 5;
    hallway.isZoneValveOpen = false;  
    hallway.ledPin = 34;    
    _gList.list[3] = hallway;  
  
    bathroom.id = 5;
    byte tmp5[] = {0x28, 0x1F, 0x84, 0xBB, 0x2, 0x0, 0x0, 0x0};
    memcpy(bathroom.sensorId, tmp5, 8);
    bathroom.name = "Bathroom";
    bathroom.prevTemp = 20;
    bathroom.winterOffset = 0;
    bathroom.summerOffset = 0;
    bathroom.setTemp = 5;  
    bathroom.curTemp = 5;  
    bathroom.isZoneValveOpen = false;  
    bathroom.ledPin = 35;    
    _gList.list[4] = bathroom;  
  
    kitchen.id = 6;
    byte tmp6[] = {0x28, 0x1F, 0x84, 0xBB, 0x2, 0x0, 0x0, 0x0};
    memcpy(kitchen.sensorId, tmp6, 8);  
    kitchen.name = "Kitchen";
    kitchen.prevTemp = 20;
    kitchen.winterOffset = 0;
    kitchen.summerOffset = 0;
    kitchen.setTemp = 5;  
    kitchen.curTemp = 5;  
    kitchen.isZoneValveOpen = false;  
    kitchen.ledPin = 36;    
    _gList.list[5] = kitchen;  
  
    livingroom.id = 7;
    byte tmp7[] = {0x28, 0x1F, 0x84, 0xBB, 0x2, 0x0, 0x0, 0x0};
    memcpy(livingroom.sensorId, tmp7, 8);
    livingroom.name = "Living Room";
    livingroom.prevTemp = 20;
    livingroom.winterOffset = 0;
    livingroom.summerOffset = 0;
    livingroom.setTemp = 5;  
    livingroom.curTemp = 5;  
    livingroom.isZoneValveOpen = false;  
    livingroom.ledPin = 37;    
    _gList.list[6] = livingroom;  
    
    outside.id = 8;
    byte tmp8[] = {0x28, 0xB5, 0x49, 0xBB, 0x02, 0x00, 0x00, 0xA2};
    memcpy(outside.sensorId, tmp8, 8);  
    outside.name = "Outside";
    outside.prevTemp = 20;
    outside.winterOffset = -3.0;
    outside.summerOffset = 0;    
    outside.setTemp = 5;  
    outside.curTemp = 5;  
    outside.isZoneValveOpen = false;  
    outside.ledPin = 38;
    _gList.list[7] = outside;       
    _gList.size = 8;
    
    
    for(int i = 0; i < _gList.size; i++)
    {
      pinMode(_gList.list[i].ledPin, OUTPUT);
    }
  
 
    Serial1.println("F0"); //0 resets the relay board
    updateCurrentTempValues();
}

void loop()
{  
  Client client = server.available();
  String html = "";
  String requestString = "";
  String content = "";
  String action; //get or set
  char buffer[128]; //buffer to read client headers
  int index = 0;
  char c;
    
  if(client.connected() && client.available())
  {
    Serial.println("Client Connected!");
    //Get Headers
    do
    {        
      c = client.read();
    
      if (index < 128)
      {        
         buffer[index] = c;
         index++;
      }
    }
    while (buffer[index-2] != '\r' && buffer[index-1] != '\n');
      
    for (int i = 0; i < sizeof(buffer); i++)
    {
      requestString += buffer[i];
    }
    
    Serial.println("DEBUG:: ");
    action = requestString.substring((requestString.indexOf('/') +1), requestString.indexOf('.'));
    //Check to see if we're updating
    Serial.println(action);
  
    //Do request
    if (action.equals("season"))
    {
      updateSeason(requestString);
      client.println("HTTP/1.0 200 OK\nServer: arduino\nCache-Control: no-store, no-cache, must-revalidate\nPragma: no-cache\nConnection: close\nContent-Type: text/html\n");
      client.print("<!DOCTYPE html PUBLIC  \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">");
      client.print("<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\"><head><meta http-equiv=\"Content-type\" content=\"text/html;charset=UTF-8\"><title>House Temps</title></head>");
      client.print("<body><h1>Data Received</h1><p>Go to <a href=\"http://172.16.11.220/get.html\">http://172.16.11.220/get.html</a> to view house status</p></body></html>");            
    }
    else if (action.equals("set"))    
    {
      setNewTemps(requestString); 
      client.println("HTTP/1.0 200 OK\nServer: arduino\nCache-Control: no-store, no-cache, must-revalidate\nPragma: no-cache\nConnection: close\nContent-Type: text/html\n");
      client.print("<!DOCTYPE html PUBLIC  \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">");
      client.print("<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\"><head><meta http-equiv=\"Content-type\" content=\"text/html;charset=UTF-8\"><title>House Temps</title></head>");
      client.print("<body><h1>Data Received</h1><p>Go to <a href=\"http://172.16.11.220/get.html\">http://172.16.11.220/get.html</a> to view house status</p></body></html>");      
    }
    else if (action.equals("get"))
    {
      client.println("HTTP/1.0 200 OK\nServer: arduino\nCache-Control: no-store, no-cache, must-revalidate\nPragma: no-cache\nConnection: close\nContent-Type: text/html\n");
      //constructHTML(client);
      client.print("<!DOCTYPE html PUBLIC  \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">");
      client.print("<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\"><head><meta http-equiv=\"Content-type\" content=\"text/html;charset=UTF-8\"><title>House Temps</title></head>");
      client.print("<body><table class=\"datatable\"><thead><tr><th>Room</th><th>Current (<sup>o</sup>C)</th><th>Target  (<sup>o</sup>C)</th><th>Status</th></tr></thead><tbody>");

      for(int i = 0; i < _gList.size; i++)
      {    
        //write name
        html += "<tr><td>";
        html += _gList.list[i].name;
        html += "</td>";            
    
        //Write current value
        html += "<td class=\"tmpdata\">";
        html += convertToString(_gList.list[i].curTemp);
        html += "</td>";  

        //Write setTemp
        html += "<td class=\"tmpdata\">";
        html += _gList.list[i].setTemp;
        html += "</td>";    
      
         //Construct Valve State
        if(_gList.list[i].isZoneValveOpen)
        {
          html +="<td><span class=\"heating\">Heating</span></td></tr>";
        }
        else
        {    
          html +="<td><span class=\"cooling\">Off</span></td></tr>";
        }
        
        client.print(html);
        html = "";
      }

      client.print("</tbody></table>");
         
      //Boiler State
      client.print("<div id=\"boilerInformation\"><h3>System Info</h3>");
      client.print("<p id=\"boilerstate\">Boiler is: ");
      if(isBoilerOn)
      {
         client.print("<span id=\"bon\">ON</span>");
      } 
      else
      {
        client.print("<span id=\"boff\">OFF</span>");
      }
      client.print("</p>");  
  
      html = "";
      //Offsets
      html += "<p id=\"upperoffsetholder\">Upper Offset: <span id=\"upperoffset\">";
      html += convertToString(UPPER_OFFSET);
      html += " (<sup>o</sup>C)";
      html += "</span></p>";
      html += "<p id=\"loweroffsetholder\">Lower Offset: <span id=\"loweroffset\">";
      html += convertToString(LOWER_OFFSET);
      html += " (<sup>o</sup>C)";  
      html += "</span></p></div>";
      html += "</body></html>";  
  
      client.print(html);    
    
      html = "";    
      Serial.print("HTML LENGTH (inc headers): ");
      Serial.println(content.length());
    }
    else if (action.equals("xml"))
    {
      content = "HTTP/1.0 200 OK\nServer: arduino\nCache-Control: no-store, no-cache, must-revalidate\nPragma: no-cache\nConnection: close\nContent-Type: text/xml\n";
      client.println(content);

      content = constructXML();
      client.println(content);
    }    

    client.flush();
    client.stop();  
  }
  else //keep on truckin'
  {
      checkZoneTemps();      
  }
}


