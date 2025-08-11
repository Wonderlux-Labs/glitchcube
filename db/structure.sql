--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Homebrew)
-- Dumped by pg_dump version 17.5 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: api_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_calls (
    id bigint NOT NULL,
    service character varying NOT NULL,
    endpoint character varying,
    method character varying,
    status_code integer,
    duration_ms integer,
    model_used character varying,
    tokens_used integer,
    request_data jsonb DEFAULT '{}'::jsonb,
    response_data jsonb DEFAULT '{}'::jsonb,
    error_message character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_calls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_calls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_calls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_calls_id_seq OWNED BY public.api_calls.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: boundaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.boundaries (
    id bigint NOT NULL,
    name character varying NOT NULL,
    boundary_type character varying NOT NULL,
    description text,
    geom public.geometry(Polygon,4326),
    properties jsonb DEFAULT '{}'::jsonb,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: boundaries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.boundaries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: boundaries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.boundaries_id_seq OWNED BY public.boundaries.id;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id bigint NOT NULL,
    session_id character varying NOT NULL,
    persona character varying,
    source character varying,
    message_count integer DEFAULT 0,
    total_cost numeric(10,6) DEFAULT 0.0,
    total_tokens integer DEFAULT 0,
    metadata jsonb DEFAULT '{}'::jsonb,
    started_at timestamp(6) without time zone,
    ended_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ha_conversation_id character varying,
    ha_device_id character varying,
    continue_conversation boolean DEFAULT true
);


--
-- Name: conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conversations_id_seq OWNED BY public.conversations.id;


--
-- Name: landmarks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.landmarks (
    id bigint NOT NULL,
    name character varying NOT NULL,
    latitude numeric(10,8) NOT NULL,
    longitude numeric(11,8) NOT NULL,
    landmark_type character varying,
    radius_meters integer DEFAULT 30,
    icon character varying,
    description text,
    properties jsonb DEFAULT '{}'::jsonb,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    location public.geometry,
    CONSTRAINT landmarks_location_consistency CHECK (((location IS NOT NULL) OR ((latitude IS NULL) AND (longitude IS NULL))))
);


--
-- Name: landmarks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.landmarks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: landmarks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.landmarks_id_seq OWNED BY public.landmarks.id;


--
-- Name: memories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memories (
    id bigint NOT NULL,
    content text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    recall_count integer DEFAULT 0,
    last_recalled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: memories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.memories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: memories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.memories_id_seq OWNED BY public.memories.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    role character varying NOT NULL,
    content text NOT NULL,
    persona character varying,
    model_used character varying,
    prompt_tokens integer,
    completion_tokens integer,
    cost numeric(10,6),
    response_time_ms integer,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.messages_id_seq OWNED BY public.messages.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: streets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.streets (
    id bigint NOT NULL,
    name character varying NOT NULL,
    street_type character varying NOT NULL,
    width integer DEFAULT 30,
    geom public.geometry(LineString,4326),
    properties jsonb DEFAULT '{}'::jsonb,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: streets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.streets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: streets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.streets_id_seq OWNED BY public.streets.id;


--
-- Name: api_calls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_calls ALTER COLUMN id SET DEFAULT nextval('public.api_calls_id_seq'::regclass);


--
-- Name: boundaries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boundaries ALTER COLUMN id SET DEFAULT nextval('public.boundaries_id_seq'::regclass);


--
-- Name: conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations ALTER COLUMN id SET DEFAULT nextval('public.conversations_id_seq'::regclass);


--
-- Name: landmarks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.landmarks ALTER COLUMN id SET DEFAULT nextval('public.landmarks_id_seq'::regclass);


--
-- Name: memories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memories ALTER COLUMN id SET DEFAULT nextval('public.memories_id_seq'::regclass);


--
-- Name: messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages ALTER COLUMN id SET DEFAULT nextval('public.messages_id_seq'::regclass);


--
-- Name: streets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streets ALTER COLUMN id SET DEFAULT nextval('public.streets_id_seq'::regclass);


--
-- Name: api_calls api_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_calls
    ADD CONSTRAINT api_calls_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: boundaries boundaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.boundaries
    ADD CONSTRAINT boundaries_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: landmarks landmarks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.landmarks
    ADD CONSTRAINT landmarks_pkey PRIMARY KEY (id);


--
-- Name: memories memories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memories
    ADD CONSTRAINT memories_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: streets streets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.streets
    ADD CONSTRAINT streets_pkey PRIMARY KEY (id);


--
-- Name: idx_boundaries_geom_geography; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_boundaries_geom_geography ON public.boundaries USING gist (((geom)::public.geography));


--
-- Name: idx_streets_geom_geography; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_streets_geom_geography ON public.streets USING gist (((geom)::public.geography));


--
-- Name: index_api_calls_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_calls_on_created_at ON public.api_calls USING btree (created_at);


--
-- Name: index_api_calls_on_service; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_calls_on_service ON public.api_calls USING btree (service);


--
-- Name: index_api_calls_on_service_and_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_calls_on_service_and_endpoint ON public.api_calls USING btree (service, endpoint);


--
-- Name: index_boundaries_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boundaries_on_active ON public.boundaries USING btree (active);


--
-- Name: index_boundaries_on_active_and_boundary_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boundaries_on_active_and_boundary_type ON public.boundaries USING btree (active, boundary_type);


--
-- Name: index_boundaries_on_boundary_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boundaries_on_boundary_type ON public.boundaries USING btree (boundary_type);


--
-- Name: index_boundaries_on_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boundaries_on_geom ON public.boundaries USING gist (geom);


--
-- Name: index_boundaries_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_boundaries_on_name ON public.boundaries USING btree (name);


--
-- Name: index_conversations_on_ha_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_ha_conversation_id ON public.conversations USING btree (ha_conversation_id);


--
-- Name: index_conversations_on_ha_conversation_id_and_ended_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_ha_conversation_id_and_ended_at ON public.conversations USING btree (ha_conversation_id, ended_at);


--
-- Name: index_conversations_on_ha_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_ha_device_id ON public.conversations USING btree (ha_device_id);


--
-- Name: index_conversations_on_persona; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_persona ON public.conversations USING btree (persona);


--
-- Name: index_conversations_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_conversations_on_session_id ON public.conversations USING btree (session_id);


--
-- Name: index_conversations_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_started_at ON public.conversations USING btree (started_at);


--
-- Name: index_landmarks_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_landmarks_on_active ON public.landmarks USING btree (active);


--
-- Name: index_landmarks_on_landmark_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_landmarks_on_landmark_type ON public.landmarks USING btree (landmark_type);


--
-- Name: index_landmarks_on_latitude_and_longitude; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_landmarks_on_latitude_and_longitude ON public.landmarks USING btree (latitude, longitude);


--
-- Name: index_landmarks_on_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_landmarks_on_location ON public.landmarks USING gist (location);


--
-- Name: index_landmarks_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_landmarks_on_name ON public.landmarks USING btree (name);


--
-- Name: index_memories_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memories_on_created_at ON public.memories USING btree (created_at);


--
-- Name: index_memories_on_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memories_on_data ON public.memories USING gin (data);


--
-- Name: index_memories_on_recall_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memories_on_recall_count ON public.memories USING btree (recall_count);


--
-- Name: index_memories_on_recall_count_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memories_on_recall_count_and_created_at ON public.memories USING btree (recall_count, created_at);


--
-- Name: index_messages_on_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_conversation_id ON public.messages USING btree (conversation_id);


--
-- Name: index_messages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_created_at ON public.messages USING btree (created_at);


--
-- Name: index_messages_on_model_used; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_model_used ON public.messages USING btree (model_used);


--
-- Name: index_messages_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_role ON public.messages USING btree (role);


--
-- Name: index_streets_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_streets_on_active ON public.streets USING btree (active);


--
-- Name: index_streets_on_active_and_street_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_streets_on_active_and_street_type ON public.streets USING btree (active, street_type);


--
-- Name: index_streets_on_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_streets_on_geom ON public.streets USING gist (geom);


--
-- Name: index_streets_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_streets_on_name ON public.streets USING btree (name);


--
-- Name: index_streets_on_street_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_streets_on_street_type ON public.streets USING btree (street_type);


--
-- Name: messages fk_rails_7f927086d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_7f927086d2 FOREIGN KEY (conversation_id) REFERENCES public.conversations(id);


--
-- PostgreSQL database dump complete
--

