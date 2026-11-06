import 'package:flutter/material.dart';

/// Catalogue des prestations AMANE.
const services = [
  'guarding', // agents de gardiennage
  'app_sub', // abonnement à l'application
  'remote', // télésurveillance
  'intervention', // protection et intervention
  'first_aid', // premiers secours
  'ambulance', // ambulances
  'devices', // installation de dispositifs de surveillance
  'emergency', // service d'urgence
  'fire_prev', // prévention incendie
  'festivals', // sécurisation de festivals
  'parties', // sécurisation de fêtes et cérémonies
  'embassies', // sécurisation d'ambassades
  'events', // sécurisation d'événements
  'sports', // sécurisation d'événements sportifs
  'banks', // sécurisation de banques
  'homes', // sécurisation de domiciles
  'financial', // sécurisation d'agences financières
  'atm', // sécurisation de distributeurs / bureaux de change
  'health', // sécurisation d'hôpitaux et cliniques
  'vip', // protection de personnalités
  'roadside', // assistance routière (panne, accident, voyage)
  'other', // autres services
];

const servicesFr = {
  'guarding': 'Agents de gardiennage',
  'app_sub': "Abonnement à l'application AMANE",
  'remote': 'Télésurveillance',
  'intervention': 'Protection et intervention',
  'first_aid': 'Premiers secours',
  'ambulance': "Service d'ambulance",
  'devices': 'Installation de dispositifs de surveillance',
  'emergency': "Service d'urgence",
  'fire_prev': 'Prévention incendie',
  'festivals': 'Sécurisation de festivals',
  'parties': 'Sécurisation de fêtes et cérémonies',
  'embassies': "Sécurisation d'ambassades",
  'sports': 'Sécurisation d’événements sportifs',
  'events': "Sécurisation d'événements",
  'banks': 'Sécurisation de banques',
  'homes': 'Sécurisation de domiciles',
  'financial': "Sécurisation d'agences financières",
  'atm': 'Sécurisation de distributeurs et bureaux de change',
  'health': "Sécurisation d'hôpitaux et cliniques",
  'vip': 'Protection de personnalités',
  'roadside': 'Assistance routière (panne, accident, voyage)',
  'other': 'Autres services',
};

IconData serviceIcon(String s) => switch (s) {
      'guarding' => Icons.badge,
      'app_sub' => Icons.phone_android,
      'remote' => Icons.videocam,
      'intervention' => Icons.local_police,
      'first_aid' => Icons.medical_services,
      'ambulance' => Icons.emergency,
      'devices' => Icons.settings_input_antenna,
      'emergency' => Icons.sos,
      'fire_prev' => Icons.local_fire_department,
      'festivals' => Icons.festival,
      'parties' => Icons.celebration,
      'embassies' => Icons.flag,
      'events' => Icons.event,
      'banks' => Icons.account_balance,
      'homes' => Icons.home,
      'financial' => Icons.currency_exchange,
      'atm' => Icons.atm,
      'health' => Icons.local_hospital,
      'vip' => Icons.star,
      'sports' => Icons.sports_soccer,
      'roadside' => Icons.car_repair,
      _ => Icons.miscellaneous_services,
    };

/// Types de sites / clients.
const siteTypes = ['office', 'individual', 'villa', 'institution', 'bank', 'agency', 'hospital', 'clinic', 'shop', 'embassy', 'event', 'other'];

const siteTypesFr = {
  'office': 'Siège / bureaux AMANE',
  'individual': 'Particulier',
  'villa': 'Villa',
  'institution': 'Institution / entreprise',
  'bank': 'Banque',
  'agency': 'Agence financière / paiement mobile',
  'hospital': 'Hôpital',
  'clinic': 'Clinique / cabinet médical',
  'shop': 'Boutique / commerce',
  'embassy': 'Ambassade',
  'event': 'Événement',
  'other': 'Autre',
};

IconData siteTypeIcon(String s) => switch (s) {
      'office' => Icons.business,
      'individual' => Icons.person,
      'villa' => Icons.villa,
      'institution' => Icons.apartment,
      'bank' => Icons.account_balance,
      'agency' => Icons.currency_exchange,
      'hospital' => Icons.local_hospital,
      'clinic' => Icons.medical_services,
      'shop' => Icons.storefront,
      'embassy' => Icons.flag,
      'event' => Icons.event,
      _ => Icons.location_on,
    };

/// Banques en activité en Mauritanie (clients « banque »).
const mauritanianBanks = [
  'Banque Populaire de Mauritanie (BPM)',
  'Banque Mauritanienne pour l\'Investissement (BMI)',
  'Banque Mauritanienne pour le Commerce International (BMCI)',
  'Banque pour le Commerce et l\'Industrie (BCI)',
  'Attijari Bank Mauritanie (ABM)',
  'Banque El Amana (BEA)',
  'Banque Al Wava Mauritanienne Islamique (BAMIS)',
  'Banque Islamique de Mauritanie (BIM)',
  'Banque de Financement et d\'Investissement (BFI)',
  'Générale de Banque de Mauritanie (GBM)',
  'Banque Nationale de Mauritanie (BNM)',
  'International Bank of Mauritania (IBM)',
  'Société Générale Mauritanie (SGM)',
  'Orabank Mauritanie',
  'Chinguitty Bank',
  'Banque Mauritanienne des Transactions Saines (BMS)',
  'Algerian Union Bank (AUB)',
  'QNB Mauritanie (QNBM)',
];

/// Agences financières et services de paiement mobile (clients « agence »).
const financialAgencies = [
  'Bankily – بنكيلي',
  'Masrvi – مصرفي',
  'Sedad – سداد',
  'BIM Bank – بيم بنك',
  'BFI Cash',
  'Mechili – مشيلي',
  'Moov Money – موف موني',
  'GazaPay – غزة باي',
  'Rassidy – رصيدي',
  'Cadorim – كادوريم',
];
