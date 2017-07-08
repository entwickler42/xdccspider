DROP DATABASE IF EXISTS XDCCSPIDER;
CREATE DATABASE XDCCSPIDER;
USE XDCCSPIDER;

CREATE TABLE server(
	id			BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
	host 		VARCHAR(32) NOT NULL,
	passwd_server	VARCHAR(32),
	passwd_nicksrv	VARCHAR(32),
	realname		VARCHAR(32),
	username		VARCHAR(32),
	nickname		VARCHAR(32),	
	port			SMALLINT UNSIGNED NOT NULL DEFAULT 6667,
	enabled		TINYINT(1) UNSIGNED NOT NULL DEFAULT 1	
);

CREATE TABLE channel(
	id			BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
	srvid		BIGINT UNSIGNED NOT NULL,
	name			VARCHAR(32) NOT NULL,
	password		VARCHAR(32),
	enabled		TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
	unique key (srvid, name)	
);

CREATE TABLE bot(
	id		BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
	chanid	BIGINT UNSIGNED NOT NULL,
	nickname	VARCHAR(32) NOT NULL,
	lastseen	DATETIME NOT NULL,
	unique key(chanid, nickname)
);

CREATE TABLE package(
	id			BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
	botid		BIGINT UNSIGNED NOT NULL,
	idx			SMALLINT UNSIGNED NOT NULL,
	description	TEXT NOT NULL,
	size			VARCHAR(12) NOT NULL,
	gets           INT UNSIGNED NOT NULL,
	lastseen 		DATETIME NOT NULL,
	unique key(botid, idx)
);

INSERT INTO server(id, host) VALUES
	(1, 'irc.criten.net'),
	(2, 'irc.frozyn.net'),
	(3, 'irc.abjects.net'),
	(4, 'irc.efnet.net')
;

INSERT INTO channel(srvid, name) VALUES
	(1, '#elitewarez'),
	(2, '#blackmarket-warez'),
	(3, '#moviegods'),
	(3, '#MEXICANMAFIA'),
	(3, '#1WAREZ'),
	(4, '#xtv')
;