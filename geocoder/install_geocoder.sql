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
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS geocoder;
CREATE SEQUENCE geocoder.communes_seq START 1;
CREATE SEQUENCE geocoder.neighborhoods_seq START 1;
CREATE SEQUENCE geocoder.road_network_seq START 1;
CREATE SEQUENCE geocoder.neighborhood_block_houseid_seq START 1;

CREATE TABLE geocoder.communes
(
	commune_id integer NOT NULL PRIMARY KEY DEFAULT nextval('geocoder.communes_seq'), --Identificacion de la comuna
	commune_name character varying (50), --Nombre de la comuna
	commune_geometry text --Geometria basada en Linea que delimita a la comuna
);
CREATE TABLE geocoder.neighborhoods
(
	neighborhood_id integer NOT NULL PRIMARY KEY DEFAULT nextval('geocoder.neighborhoods_seq'), --Identificacion del barrio
	neighborhood_name varchar(50), --Nombre del barrio
	commune_id integer REFERENCES geocoder.communes(commune_id),--Identificador de la comuna
	neighborhood_geometry text --Geometria basada en Linea que delimita al barrio
);
CREATE TABLE geocoder.road_network_addresses
(
	address_id integer NOT NULL PRIMARY KEY DEFAULT nextval('geocoder.road_network_seq'), --Identificacion de la direccion
	main_road character varying(20), --Via principal
	generated_road character varying(20), --Via generadora o secundaria
	distance integer, --Distancia entre la interseccion de las vias principal y generadora y el predio
	neighborhood_id integer REFERENCES geocoder.neighborhoods(neighborhood_id), --Identificacion del barrio al que pertenece el barrio
	lon double precision,
	lat double precision
);
CREATE TABLE geocoder.neighborhood_block_houseid_addresses
(
	address_id integer NOT NULL PRIMARY KEY DEFAULT nextval('geocoder.neighborhood_block_houseid_seq'), --Identificacion de la direccion
	block character varying(10), --Nombre o identificacion de la manzana
	houseid character varying(10), --Numero o identificacion de la casa
	neighborhood_id integer REFERENCES geocoder.neighborhoods(neighborhood_id),
	lon double precision,
	lat double precision
);
CREATE TYPE road_network_type AS (
	main_road character varying,
	generated_road character varying,
	distance integer
);CREATE TYPE neighborhood_block_houseid_type AS (
	neighborhood character varying (40),
	block character varying (10),
	houseid character varying (10)
);CREATE TYPE geocode_address_type AS (
	address character varying (25),
	neighborhood character varying (50),
	commune character varying (50),
	lon double precision,
	lat double precision
);
CREATE OR REPLACE FUNCTION normalize_address(addr text) RETURNS road_network_type AS
$$
DECLARE
	address character varying;
	address_array character varying[];
	main_road character varying;
	generated_road character varying;
	distance character varying;
	result road_network_type;
	state integer;
	array_element character varying;
	aux character varying (8); 
BEGIN
	address := upper(addr);
	address := regexp_replace(address, '^K ', 'KR ', 'g');
	address := regexp_replace(address, '^C ','CL ', 'g');
	address := regexp_replace(address, 'DIAGONAL|DIAG','DG ','g');	
	address := regexp_replace(address, 'CARRERA|KARRERA|CRRA|KRRA|CRA|KRA|KR|CR|CARERA|[CK]+[R]+','KR ','g');
	address := regexp_replace(address, 'CALLE|CALL|CLLE|CLL|CL|CAL|CLE|CALE|ALLE|ACLLE|[C]+[L]+','CL ','g');
	address := regexp_replace(address, 'NORTE',' NORTE ','g');
	address := regexp_replace(address, 'SUR',' SUR ','g');
	address := regexp_replace(address, 'ESTE',' ESTE ','g');
	address := regexp_replace(address, 'OESTE|O ESTE',' OESTE ','g');
	address := regexp_replace(address, 'BIS',' BIS ','g');
	address := regexp_replace(address, '[[:punct:]]', ' ', 'g');
	address := regexp_replace(address, ' N |NO|NUMERO|NUM',' ','g');
	address_array := array_remove(string_to_array(address, ' '), '');

	state := 0;
	FOREACH array_element IN ARRAY address_array
	LOOP
		IF array_element SIMILAR TO '[MZCS]{2}' THEN
			state := 0;
		END IF;
		IF state = 0 THEN
			IF array_element SIMILAR TO '[CL]{1,2}' THEN
				main_road := 'CL ';
				state := 1;
			ELSIF array_element SIMILAR TO '[KR]{1,2}' THEN
				main_road := 'KR ';
				state := 1;
			ELSIF array_element SIMILAR TO '[DG]{2}' THEN
				main_road := 'DG ';
				state := 1;
			END IF;
		ELSIF state = 1 THEN
			IF array_element SIMILAR TO '[0-9]{1,3}' THEN
				main_road := main_road || CAST(array_element AS integer)|| ' ';
				state := 2;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}[A-Z]{1}' THEN
				aux := array_to_string(regexp_matches(array_element, '[0-9]{1,3}'),'');
				main_road := main_road || CAST(aux AS integer)|| ' ';
				aux := array_to_string(regexp_matches(array_element, '[A-Z]{1}'),'');
				main_road := main_road || aux || ' ';
				state := 2;
			END IF;
		ELSIF state = 2 THEN
			IF array_element SIMILAR TO '[A-Z]' OR array_element SIMILAR TO 'BIS' OR array_element SIMILAR TO 'NORTE|SUR|ESTE|OESTE' THEN
				main_road := main_road || array_element || ' ';
				state := 2;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}' THEN
				generated_road := CAST(array_element AS integer) || ' ';
				state := 3;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}[A-Z]{1}' THEN
				aux := array_to_string(regexp_matches(array_element, '[0-9]{1,3}'),'');
				generated_road := CAST(aux as integer)|| ' ';
				aux := array_to_string(regexp_matches(array_element, '[A-Z]{1}'),'');
				generated_road := generated_road || aux || ' ';
				state := 3;
			END IF;
		ELSIF state = 3 THEN
			IF array_element SIMILAR TO '[A-Z]{1}' OR array_element SIMILAR TO 'BIS' OR array_element SIMILAR TO 'NORTE|SUR|ESTE|OESTE' THEN
				generated_road := generated_road || array_element || ' ';
				state := 3;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}' THEN
				distance:= cast(array_element as integer);
				state := 4;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}[A-Z]{1}' THEN
				distance := array_to_string(regexp_matches(array_element, '[0-9]{1,3}'),'');
				distance := CAST (distance AS integer);
				state := 4;
			END IF;
		END IF;		
	END LOOP;
	IF state > 3 THEN
		result.main_road := substring(main_road ,1 ,length(main_road) - 1);
		result.generated_road := substring(generated_road ,1 ,length(generated_road) - 1);
		result.distance := distance;
	ELSE
		result := NULL;
	END IF;
	
	RETURN result;

	EXCEPTION
		WHEN null_value_not_allowed THEN RETURN NULL;
END;
$$
LANGUAGE plpgsql VOLATILE;
CREATE OR REPLACE FUNCTION geocode_address(addr text) RETURNS geocode_address_type AS
$$
DECLARE
	normalized_address road_network_type;
	neighborhood character varying;
	commune character varying;
	longitude double precision;
	latitude double precision;
	result geocode_address_type;
BEGIN
	normalized_address := normalize_address(addr);
	SELECT 
		neighborhood_name, commune_name, lon, lat INTO neighborhood, commune, longitude, latitude
	FROM
		geocoder.road_network_addresses NATURAL JOIN geocoder.neighborhoods NATURAL JOIN geocoder.communes
	WHERE
		main_road = normalized_address.main_road AND
		regexp_replace(generated_road, '[CLKRDG]{2} ','') = normalized_address.generated_road AND
		distance = CAST(normalized_address.distance AS integer);
	result.address := normalized_address.main_road ||' '|| normalized_address.generated_road ||' '||normalized_address.distance;
	result.neighborhood := neighborhood;
	result.commune := commune;
	result.lon := longitude;
	result.lat := latitude;

	IF result.lon IS NULL AND result.lat IS NULL THEN
		RETURN NULL;
	ELSE	
		RETURN result;
	END IF;

END;
$$
LANGUAGE plpgsql VOLATILE;
CREATE OR REPLACE FUNCTION normalize_address (neighb text, addr text) RETURNS neighborhood_block_houseid_type AS
$$
DECLARE
	address character varying;
	searched_neighborhood character varying;
	searched_block character varying;
	searched_houseid character varying;
	
	address_array character varying[];
	array_element character varying;
	state integer;
	result neighborhood_block_houseid_type;
BEGIN
	address := upper(addr);
	address := regexp_replace(address, '^M |^MA |MANZANA|MANZ|MZNA|MNZ|MAZ|MAN|MN|MZA|MZ',' MZ ','g');
	address := regexp_replace(address, 'C+A*S+A*|CON',' CS ','g');
	address := regexp_replace(address, '[[:punct:]]', ' ', 'g');
	address_array := array_remove(string_to_array(address, ' '), '');
	
	searched_neighborhood := upper(neighb);
	searched_neighborhood := regexp_replace(searched_neighborhood, '[[:punct:]]', ' ', 'g');
	searched_neighborhood := regexp_replace(searched_neighborhood, 'BARRIO |BR ','','g');

	state := 0;
	FOREACH array_element IN ARRAY address_array
	LOOP
		IF state = 0 THEN
			IF array_element SIMILAR TO '[MZ]{2}' THEN
				searched_block := 'MZ ';
				state := 1;
			END IF;
		ELSIF state = 1 THEN
			IF array_element SIMILAR TO '[0-9]{1,3}' OR array_element SIMILAR TO '[A-Z]{1}' OR array_element SIMILAR TO '[0-9]{1,3}[A-Z]{1}' OR array_element SIMILAR TO '[A-Z]{1}[0-9]{1}' THEN
				searched_block := searched_block || array_element;
				state := 2;
			END IF;
		ELSIF state = 2 THEN
			IF array_element SIMILAR TO '[A-Z]{1}' THEN
				searched_houseid := array_element;
				state := 3;
			ELSIF array_element SIMILAR TO '[CS]{2}' THEN
				searched_houseid := 'CS ';
				state := 3;
			END IF;
		ELSIF state = 3 THEN
			IF array_element SIMILAR TO '[CS]{1,2}' THEN
				searched_block = searched_block || ' ' || searched_houseid;
				searched_houseid = 'CS ';
				state = 3;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}' THEN
				searched_houseid := 'CS ' || array_element;
				state := 4;
			ELSIF array_element SIMILAR TO '[0-9]{1,3}[A-Z]{1}' THEN
				searched_houseid := 'CS ' || array_element;
				state := 4;
			END IF;
		ELSIF state = 4 THEN
			IF array_element SIMILAR TO '[A-Z]{1,3}' THEN
				searched_houseid := searched_houseid || array_element;
				state := 4;
			END IF;
		END IF;
	END LOOP;

	IF state > 3 THEN
 		searched_neighborhood := nh.neighborhood_name 
 			FROM (geocoder.neighborhood_block_houseid_addresses NATURAL JOIN geocoder.neighborhoods) nh
 			WHERE jarowinkler(nh.neighborhood_name, searched_neighborhood) > 0.9 AND nh.block = searched_block AND 'CS '||regexp_replace(houseid, ' ', '', 'g') = searched_houseid
 			ORDER BY jarowinkler(nh.neighborhood_name, searched_neighborhood) DESC LIMIT 1;
 		IF searched_neighborhood IS NOT NULL THEN
 			result.neighborhood := searched_neighborhood;
 			result.block := searched_block;
 			result.houseid := searched_houseid;
		END IF;
	END IF;
	--RAISE NOTICE 'VALOR ESTADO: (%)', state;
	--RAISE NOTICE 'VALOR MANZANA: (%)', searched_block;
	--RAISE NOTICE 'VALOR CASA: (%)', searched_houseid;
	RETURN result;
	--Excepcion para valores nulos ingresados 
	EXCEPTION
		WHEN null_value_not_allowed THEN RETURN NULL;
END;
$$
LANGUAGE plpgsql VOLATILE;
CREATE OR REPLACE FUNCTION geocode_address (neigh text, addr text) RETURNS geocode_address_type AS
$$
DECLARE
	address neighborhood_block_houseid_type;
	commune character varying;
	longitude double precision;
	latitude double precision;

	result geocode_address_type;
BEGIN
	address := normalize_address(neigh, addr);
	SELECT
		commune_name, lon, lat INTO commune, longitude, latitude
	FROM
		geocoder.neighborhood_block_houseid_addresses NATURAL JOIN geocoder.neighborhoods NATURAL JOIN geocoder.communes
	WHERE
		neighborhood_name = address.neighborhood AND
		block = address.block AND
		'CS '||houseid = address.houseid;
	result.neighborhood := address.neighborhood;
	result.address := address.block || ' ' || address.houseid;
	result.commune := commune;
	result.lon := longitude;
	result.lat := latitude;
		
	IF result.lon IS NULL AND result.lat IS NULL THEN
		RETURN NULL;
	ELSE	
		RETURN result;
	END IF;
END;
$$
LANGUAGE plpgsql VOLATILE;
