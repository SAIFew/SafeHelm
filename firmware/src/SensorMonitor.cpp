#include "SensorMonitor.h"
void SensorMonitor::begin(){ analogReadResolution(12); }
void SensorMonitor::update(){
  if(millis()-lastSample_ < Config::SAMPLE_INTERVAL_MS) return; lastSample_=millis();
  const int pins[]={Config::FORCE_SENSOR_LEFT_PIN,Config::FORCE_SENSOR_RIGHT_PIN,Config::FORCE_SENSOR_CENTER_PIN}; uint8_t aboveCount=0;
  for(int i=0;i<3;i++){ uint16_t raw=analogRead(pins[i]); filtered_[i]=(filtered_[i]*3+raw)/4; if(filtered_[i]>=Config::ACCIDENT_THRESHOLD) aboveCount++; }
  if(Config::SAFEHELM_CALIBRATION) Serial.printf("force %u %u %u\n",filtered_[0],filtered_[1],filtered_[2]);
  // A confirmed accident requires at least two of the three FSRs above threshold.
  if(aboveCount>=2){ if(!aboveSince_) aboveSince_=millis(); } else aboveSince_=0;
}
bool SensorMonitor::confirmed()const{return aboveSince_ && millis()-aboveSince_>=Config::CONFIRMATION_MS;}
bool SensorMonitor::belowThreshold()const{uint8_t aboveCount=0;for(const auto value:filtered_)if(value>=Config::ACCIDENT_THRESHOLD)aboveCount++;return aboveCount<2;}
void SensorMonitor::clear(){aboveSince_=0;}
