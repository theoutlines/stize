part of 'map_style.dart';

// The data-viz basemap: the same style in quiet greys, for Coverage. The city
// keeps its shape (water, roads, buildings) but gives up every colour, so the
// transit colours on top are the only ones on screen. Like MapTiler's Dataviz
// style, built from our own layers.

const _lightDataviz = _Palette(
  bg: '#EDEEF0',
  built: '#E8E9EB',
  industrial: '#E6E7E9',
  school: '#E8E9EB',
  hospital: '#E8E9EB',
  water: '#D5D8DD',
  waterText: '#A3A7AE',
  park: '#E4E6E6',
  wood: '#E2E4E4',
  grass: '#E5E7E7',
  pitch: '#E3E5E5',
  roadMinor: '#F6F6F7',
  roadMajor: '#FAFAFB',
  roadMotor: '#FFFFFF',
  path: '#F2F2F3',
  rail: '#DADCE0',
  roof: '#E3E4E7',
  wall: '#DCDEE2',
  flatBuilding: '#E3E4E7',
  buildingLine: '#DCDEE2',
  text: '#8E939B',
  road: '#A3A7AE',
  soft: '#A3A7AE',
  halo: 'rgba(237,238,240,0.9)',
  boundary: '#D2D5DA',
  light: 0.2,
);

const _darkDataviz = _Palette(
  bg: '#0E0F14',
  built: '#12131A',
  industrial: '#121319',
  school: '#12131A',
  hospital: '#12131A',
  water: '#0A0B0F',
  waterText: '#4A4E5A',
  park: '#111318',
  wood: '#101217',
  grass: '#111318',
  pitch: '#111318',
  roadMinor: '#17181F',
  roadMajor: '#1A1C24',
  roadMotor: '#1E2029',
  path: '#15161C',
  rail: '#1A1C23',
  roof: '#1A1B22',
  wall: '#15161C',
  flatBuilding: '#17181F',
  buildingLine: '#14151B',
  text: '#5A5E6A',
  road: '#4A4E5A',
  soft: '#4A4E5A',
  halo: 'rgba(14,15,20,0.9)',
  boundary: '#22242C',
  light: 0.12,
);
