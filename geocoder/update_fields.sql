--
--  install_geocoder.sql
--  
--  Copyright 2016 Nelson Enrique Quemá Taimbud <nelson8533@gmail.com>
-- 
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 3 of the License, or
-- (at your option) any later version.
--  
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--  
-- You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
--  MA 02110-1301, USA.
--
--
UPDATE
	geocoder.neighborhoods
SET 
	commune_id = cm.commune_id
FROM
	geocoder.neighborhoods nh, geocoder.communes cm
WHERE
	ST_Contains(ST_Buffer(ST_GeomFromText(cm.commune_geometry), 2),nh.neighborhood_geometry) IS TRUE AND
	nh.neighborhood_id = neighborhoods.neighborhood_id;
UPDATE 
	geocoder.road_network_addresses
SET 
	neighborhood_id = nh.neighborhood_id
FROM
	geocoder.road_network_addresses addr, geocoder.neighborhoods nh
WHERE
	ST_Contains(ST_GeomFromText(nh.neighborhood_geometry), ST_MakePoint(addr.lon, addr.lat)) IS TRUE AND
	addr.address_id = road_network_addresses.address_id;

UPDATE 
	geocoder.neighborhood_block_houseid_addresses
SET 
	neighborhood_id = nh.neighborhood_id
FROM
	geocoder.neighborhood_block_houseid_addresses addr, geocoder.neighborhoods nh
WHERE
	ST_Contains(ST_GeomFromText(nh.neighborhood_geometry), ST_MakePoint(addr.lon, addr.lat)) IS TRUE AND
	addr.address_id = neighborhood_block_houseid_addresses.address_id;

