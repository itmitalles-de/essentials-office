<?php

declare(strict_types=1);

script('appointments', 'common');
script('appointments', 'internal');
style('appointments', 'vendor/simple-business-tokens');
style('appointments', 'appointments');

/** @var \OCP\IL10N $l */
$apiBase = (string)($_['apiBase'] ?? '/apps/appointments/api/v1');
$weekdays = [
	1 => $l->t('Monday'),
	2 => $l->t('Tuesday'),
	3 => $l->t('Wednesday'),
	4 => $l->t('Thursday'),
	5 => $l->t('Friday'),
	6 => $l->t('Saturday'),
	7 => $l->t('Sunday'),
];
?>
<div id="app-content"
	 class="appointments-app"
	 data-api-base="<?php p($apiBase); ?>">
	<section id="appointments-onboarding" class="appointments-onboarding" data-testid="org-onboarding" hidden aria-labelledby="appointments-onboarding-title">
		<div class="appointments-onboarding-card">
			<img class="appointments-brand-icon" src="<?php p(image_path('appointments', 'app.svg')); ?>" alt="">
			<h1 id="appointments-onboarding-title"><?php p($l->t('Set up appointments')); ?></h1>
			<p><?php p($l->t('Create your organization to start offering services and bookable times.')); ?></p>
			<form id="appointments-onboarding-form" class="appointments-form appointments-form-narrow">
				<label for="appointments-onboarding-name"><?php p($l->t('Organization name')); ?></label>
				<input id="appointments-onboarding-name" name="name" type="text" autocomplete="organization" required maxlength="160">
				<label for="appointments-onboarding-slug"><?php p($l->t('Booking page address')); ?></label>
				<div class="appointments-input-prefix">
					<span aria-hidden="true">/apps/appointments/book/</span>
					<input id="appointments-onboarding-slug" name="slug" type="text" inputmode="url" required maxlength="80" pattern="[a-z0-9]+(?:-[a-z0-9]+)*" aria-describedby="appointments-onboarding-slug-help">
				</div>
				<p id="appointments-onboarding-slug-help" class="appointments-help"><?php p($l->t('Use lower-case letters, numbers, and hyphens.')); ?></p>
				<label for="appointments-onboarding-timezone"><?php p($l->t('Time zone')); ?></label>
				<input id="appointments-onboarding-timezone" name="timezone" type="text" value="Europe/Berlin" required>
				<label for="appointments-onboarding-locale"><?php p($l->t('Default language')); ?></label>
				<select id="appointments-onboarding-locale" name="locale">
					<option value="de" selected><?php p($l->t('German')); ?></option>
					<option value="en"><?php p($l->t('English')); ?></option>
				</select>
				<button class="primary" type="submit" data-testid="organization-create"><?php p($l->t('Create organization')); ?></button>
			</form>
		</div>
	</section>

	<div id="appointments-workspace" class="appointments-shell" hidden>
		<nav class="appointments-sidebar" aria-label="<?php p($l->t('Appointment sections')); ?>">
			<div class="appointments-sidebar-title">
				<img class="appointments-brand-icon" src="<?php p(image_path('appointments', 'app.svg')); ?>" alt="">
				<span><?php p($l->t('Appointments')); ?></span>
			</div>
			<button type="button" data-section-target="calendar" aria-current="page"><?php p($l->t('Calendar')); ?></button>
			<button type="button" data-section-target="services"><?php p($l->t('Services')); ?></button>
			<button type="button" data-section-target="staff"><?php p($l->t('Staff')); ?></button>
			<button type="button" data-section-target="locations"><?php p($l->t('Locations')); ?></button>
			<button type="button" data-section-target="resources"><?php p($l->t('Resources')); ?></button>
			<button type="button" data-section-target="availability"><?php p($l->t('Availability')); ?></button>
			<button type="button" data-section-target="booking-page"><?php p($l->t('Booking page')); ?></button>
			<button type="button" data-section-target="operations"><?php p($l->t('Notifications and integrations')); ?></button>
		</nav>

		<main class="appointments-main">
			<header class="appointments-page-header">
				<div>
					<h1 id="appointments-page-title"><?php p($l->t('Appointments')); ?></h1>
					<p id="appointments-page-subtitle" class="appointments-muted"><?php p($l->t('Manage bookings and availability.')); ?></p>
				</div>
				<div class="appointments-header-actions">
					<label class="appointments-visually-hidden" for="appointments-organization"><?php p($l->t('Organization')); ?></label>
					<select id="appointments-organization" data-testid="organization-select" aria-label="<?php p($l->t('Organization')); ?>"></select>
					<button id="appointments-new" class="primary" type="button"><?php p($l->t('New appointment')); ?></button>
				</div>
			</header>

			<div id="appointments-status" class="appointments-status" role="status" aria-live="polite"></div>

			<section class="appointments-panel" data-section-panel="calendar" aria-labelledby="appointments-calendar-title">
				<h2 id="appointments-calendar-title" class="appointments-visually-hidden"><?php p($l->t('Appointment calendar')); ?></h2>
				<div class="appointments-toolbar">
					<div class="appointments-search">
						<label class="appointments-visually-hidden" for="appointments-search"><?php p($l->t('Search appointments')); ?></label>
						<input id="appointments-search" type="search" placeholder="<?php p($l->t('Search name, email, phone, or booking number')); ?>">
					</div>
					<div class="appointments-view-switch" role="group" aria-label="<?php p($l->t('Calendar view')); ?>">
						<button type="button" data-view="list" aria-pressed="true"><?php p($l->t('List')); ?></button>
						<button type="button" data-view="day" aria-pressed="false"><?php p($l->t('Day')); ?></button>
						<button type="button" data-view="week" aria-pressed="false"><?php p($l->t('Week')); ?></button>
						<button type="button" data-view="month" aria-pressed="false"><?php p($l->t('Month')); ?></button>
					</div>
				</div>

				<div class="appointments-filters" aria-label="<?php p($l->t('Appointment filters')); ?>">
					<label><?php p($l->t('Staff')); ?><select id="appointments-filter-staff"><option value=""><?php p($l->t('All staff')); ?></option></select></label>
					<label><?php p($l->t('Location')); ?><select id="appointments-filter-location"><option value=""><?php p($l->t('All locations')); ?></option></select></label>
					<label><?php p($l->t('Service')); ?><select id="appointments-filter-service"><option value=""><?php p($l->t('All services')); ?></option></select></label>
					<label><?php p($l->t('Status')); ?>
						<select id="appointments-filter-status">
							<option value=""><?php p($l->t('All statuses')); ?></option>
							<option value="pending"><?php p($l->t('Pending')); ?></option>
							<option value="confirmed"><?php p($l->t('Confirmed')); ?></option>
							<option value="cancelled_by_customer"><?php p($l->t('Cancelled by customer')); ?></option>
							<option value="cancelled_by_staff"><?php p($l->t('Cancelled by staff')); ?></option>
							<option value="completed"><?php p($l->t('Completed')); ?></option>
							<option value="no_show"><?php p($l->t('No-show')); ?></option>
							<option value="rescheduled"><?php p($l->t('Rescheduled')); ?></option>
						</select>
					</label>
					<label><?php p($l->t('Resource')); ?><select id="appointments-filter-resource"><option value=""><?php p($l->t('All resources')); ?></option></select></label>
					<button id="appointments-clear-filters" type="button"><?php p($l->t('Clear filters')); ?></button>
				</div>

				<div class="appointments-date-navigation">
					<div class="appointments-button-group">
						<button id="appointments-period-previous" type="button" aria-label="<?php p($l->t('Previous period')); ?>"><?php p($l->t('Previous')); ?></button>
						<button id="appointments-period-today" type="button"><?php p($l->t('Today')); ?></button>
						<button id="appointments-period-next" type="button" aria-label="<?php p($l->t('Next period')); ?>"><?php p($l->t('Next')); ?></button>
					</div>
					<h3 id="appointments-period-label"></h3>
				</div>
				<div id="appointments-calendar" class="appointments-calendar" data-testid="internal-calendar" aria-live="polite" aria-busy="true"></div>
			</section>

			<?php foreach (['services' => 'Services', 'staff' => 'Staff', 'locations' => 'Locations', 'resources' => 'Resources'] as $section => $label): ?>
				<section class="appointments-panel" data-section-panel="<?php p($section); ?>" hidden aria-labelledby="appointments-<?php p($section); ?>-title">
					<div class="appointments-section-heading">
						<div>
							<h2 id="appointments-<?php p($section); ?>-title"><?php p($l->t($label)); ?></h2>
							<p class="appointments-muted"><?php p($l->t('Configure what customers can book.')); ?></p>
						</div>
						<button class="primary" type="button" data-config-create="<?php p($section); ?>" data-testid="<?php p(rtrim($section, 's') . '-create'); ?>"><?php p($l->t('Add new')); ?></button>
					</div>
					<div id="appointments-<?php p($section); ?>-list" class="appointments-card-grid" data-testid="<?php p(rtrim($section, 's') . '-list'); ?>"></div>
				</section>
			<?php endforeach; ?>

			<section class="appointments-panel" data-section-panel="availability" hidden aria-labelledby="appointments-availability-title">
				<div class="appointments-section-heading">
					<div>
						<h2 id="appointments-availability-title"><?php p($l->t('Availability')); ?></h2>
						<p class="appointments-muted"><?php p($l->t('Define regular weekly hours for the organization, services, staff, locations, and resources.')); ?></p>
					</div>
				</div>
				<form id="appointments-availability-form" class="appointments-form" data-testid="availability-form">
					<div class="appointments-form-grid">
						<label><?php p($l->t('Subject type')); ?>
							<select id="appointments-availability-type" name="subjectType">
								<option value="organization"><?php p($l->t('Organization')); ?></option>
								<option value="service"><?php p($l->t('Service')); ?></option>
								<option value="staff"><?php p($l->t('Staff member')); ?></option>
								<option value="location"><?php p($l->t('Location')); ?></option>
								<option value="resource"><?php p($l->t('Resource')); ?></option>
							</select>
						</label>
						<label><?php p($l->t('Subject')); ?><select id="appointments-availability-subject" name="subjectId" data-testid="availability-subject" required></select></label>
						<label><?php p($l->t('Time zone')); ?><input id="appointments-availability-timezone" name="timezone" type="text" value="Europe/Berlin" readonly></label>
					</div>
					<div class="appointments-weekly-hours">
						<?php foreach ($weekdays as $number => $weekday): ?>
							<fieldset data-weekday="<?php p((string)$number); ?>">
								<legend><?php p($weekday); ?></legend>
								<label class="appointments-inline-check"><input type="checkbox" name="weekday-<?php p((string)$number); ?>-enabled" <?php if ($number <= 5): ?>checked<?php endif; ?>> <?php p($l->t('Available')); ?></label>
								<label><?php p($l->t('Start')); ?><input type="time" name="weekday-<?php p((string)$number); ?>-start" value="09:00"></label>
								<label><?php p($l->t('End')); ?><input type="time" name="weekday-<?php p((string)$number); ?>-end" value="17:00"></label>
							</fieldset>
						<?php endforeach; ?>
					</div>
					<fieldset class="appointments-availability-extra">
						<legend><?php p($l->t('Recurring breaks')); ?></legend>
						<p class="appointments-help"><?php p($l->t('Breaks block time within otherwise available weekly hours.')); ?></p>
						<div id="appointments-break-rows" class="appointments-rule-rows"></div>
						<button id="appointments-add-break" type="button"><?php p($l->t('Add recurring break')); ?></button>
					</fieldset>
					<fieldset class="appointments-availability-extra">
						<legend><?php p($l->t('One-time exceptions')); ?></legend>
						<p class="appointments-help"><?php p($l->t('Add special opening times, blocked periods, vacation, or holidays without hard-coding dates.')); ?></p>
						<div id="appointments-exception-rows" class="appointments-rule-rows"></div>
						<button id="appointments-add-exception" type="button"><?php p($l->t('Add exception')); ?></button>
					</fieldset>
					<div class="appointments-form-actions"><button class="primary" type="submit" data-testid="availability-submit"><?php p($l->t('Save availability')); ?></button></div>
				</form>
			</section>

			<section class="appointments-panel" data-section-panel="booking-page" hidden aria-labelledby="appointments-booking-page-title">
				<div class="appointments-section-heading">
					<div>
						<h2 id="appointments-booking-page-title"><?php p($l->t('Booking page settings')); ?></h2>
						<p class="appointments-muted"><?php p($l->t('Customize the public information without adding custom HTML or scripts.')); ?></p>
					</div>
					<a id="appointments-booking-page-link" class="button" target="_blank" rel="noopener noreferrer" hidden><?php p($l->t('Open booking page')); ?></a>
				</div>
				<form id="appointments-settings-form" class="appointments-form">
					<div class="appointments-form-grid">
						<label><?php p($l->t('Public organization name')); ?><input name="name" type="text" maxlength="255" required></label>
						<label><?php p($l->t('Default language')); ?><select name="locale"><option value="de"><?php p($l->t('German')); ?></option><option value="en"><?php p($l->t('English')); ?></option></select></label>
						<label><?php p($l->t('Time zone')); ?><input name="timezone" type="text" required></label>
						<label><?php p($l->t('Accent color')); ?><input name="accentColor" type="color" value="#00679e"></label>
					</div>
					<label><?php p($l->t('Description')); ?><textarea name="description" rows="4" maxlength="2000"></textarea></label>
					<label><?php p($l->t('Contact information')); ?><textarea name="contactInfo" rows="3" maxlength="2000"></textarea></label>
					<div class="appointments-form-grid">
						<label><?php p($l->t('Privacy policy URL')); ?><input name="privacyUrl" type="url" inputmode="url"></label>
						<label><?php p($l->t('Legal notice URL')); ?><input name="imprintUrl" type="url" inputmode="url"></label>
						<label><?php p($l->t('Slot interval')); ?><select name="slotInterval"><option value="5"><?php p($l->t('5 minutes')); ?></option><option value="10"><?php p($l->t('10 minutes')); ?></option><option value="15"><?php p($l->t('15 minutes')); ?></option><option value="30"><?php p($l->t('30 minutes')); ?></option></select></label>
						<label><?php p($l->t('Minimum form time in seconds')); ?><input name="minimumFormSeconds" type="number" min="2" max="120"></label>
						<label><?php p($l->t('Customer data retention in days')); ?><input name="retentionDays" type="number" min="30" max="3650"></label>
						<label class="appointments-inline-check"><input name="publicEnabled" type="checkbox"> <?php p($l->t('Public booking enabled')); ?></label>
					</div>
					<label><?php p($l->t('Booking confirmation text')); ?><textarea name="confirmationText" rows="4" maxlength="4000"></textarea></label>
					<div class="appointments-form-actions"><button class="primary" type="submit"><?php p($l->t('Save settings')); ?></button></div>
				</form>
			</section>

			<section class="appointments-panel" data-section-panel="operations" hidden aria-labelledby="appointments-operations-title">
				<div class="appointments-section-heading">
					<div>
						<h2 id="appointments-operations-title"><?php p($l->t('Notifications and integrations')); ?></h2>
						<p class="appointments-muted"><?php p($l->t('Recent delivery and synchronization failures without customer data.')); ?></p>
					</div>
				</div>
				<div id="appointments-operations-list" class="appointments-operation-list" aria-live="polite"></div>
			</section>
		</main>
	</div>

	<dialog id="appointments-editor" class="appointments-dialog" aria-labelledby="appointments-editor-title">
		<form id="appointments-editor-form" class="appointments-form" data-testid="appointment-form">
			<div class="appointments-dialog-header">
				<h2 id="appointments-editor-title"><?php p($l->t('New appointment')); ?></h2>
				<button type="button" class="appointments-dialog-close" data-dialog-close aria-label="<?php p($l->t('Close')); ?>">×</button>
			</div>
			<input name="appointmentId" type="hidden">
			<div class="appointments-form-grid" data-appointment-full-fields>
				<label><?php p($l->t('First name')); ?><input name="firstName" type="text" autocomplete="given-name" required maxlength="100"></label>
				<label><?php p($l->t('Last name')); ?><input name="lastName" type="text" autocomplete="family-name" required maxlength="100"></label>
				<label><?php p($l->t('Email')); ?><input name="email" type="email" autocomplete="email" required maxlength="254"></label>
				<label><?php p($l->t('Phone')); ?><input name="phone" type="tel" autocomplete="tel" maxlength="50"></label>
				<label><?php p($l->t('Service')); ?><select name="serviceId" required></select></label>
				<label><?php p($l->t('Staff')); ?><select name="staffId" required></select></label>
				<label><?php p($l->t('Location')); ?><select name="locationId"></select></label>
				<label><?php p($l->t('Date and time')); ?><input name="startsAtLocal" type="datetime-local" required></label>
				<label><?php p($l->t('Status')); ?>
					<select name="status">
						<option value="pending"><?php p($l->t('Pending')); ?></option>
						<option value="confirmed"><?php p($l->t('Confirmed')); ?></option>
						<option value="cancelled_by_customer"><?php p($l->t('Cancelled by customer')); ?></option>
						<option value="cancelled_by_staff"><?php p($l->t('Cancelled by staff')); ?></option>
						<option value="completed"><?php p($l->t('Completed')); ?></option>
						<option value="no_show"><?php p($l->t('No-show')); ?></option>
						<option value="rescheduled"><?php p($l->t('Rescheduled')); ?></option>
					</select>
				</label>
			</div>
			<p id="appointments-editor-timezone" class="appointments-help" data-appointment-full-fields></p>
			<label data-appointment-full-fields><?php p($l->t('Customer note')); ?><textarea name="customerNote" rows="3" maxlength="4000"></textarea></label>
			<fieldset id="appointments-editor-custom-fields" class="appointments-form-fields-editor" data-appointment-full-fields hidden>
				<legend><?php p($l->t('Booking form answers')); ?></legend>
				<div id="appointments-editor-custom-field-controls" class="appointments-form appointments-form-grid"></div>
			</fieldset>
			<label><?php p($l->t('Internal note')); ?><textarea name="internalNote" rows="3" maxlength="4000" aria-describedby="appointments-internal-note-help"></textarea></label>
			<p id="appointments-internal-note-help" class="appointments-help"><?php p($l->t('Internal notes are never shown to customers.')); ?></p>
			<div class="appointments-form-actions">
				<button type="button" data-dialog-close><?php p($l->t('Cancel')); ?></button>
				<button id="appointments-editor-submit" class="primary" type="submit" data-testid="appointment-submit"><?php p($l->t('Save appointment')); ?></button>
			</div>
		</form>
	</dialog>

	<dialog id="appointments-config-editor" class="appointments-dialog" aria-labelledby="appointments-config-title">
		<form id="appointments-config-form" class="appointments-form">
			<div class="appointments-dialog-header">
				<h2 id="appointments-config-title"><?php p($l->t('Edit configuration')); ?></h2>
				<button type="button" class="appointments-dialog-close" data-dialog-close aria-label="<?php p($l->t('Close')); ?>">×</button>
			</div>
			<input name="configType" type="hidden">
			<input name="configId" type="hidden">
			<div id="appointments-config-fields" class="appointments-form-grid"></div>
			<div class="appointments-form-actions">
				<button type="button" data-dialog-close><?php p($l->t('Cancel')); ?></button>
				<button class="primary" type="submit"><?php p($l->t('Save')); ?></button>
			</div>
		</form>
	</dialog>
</div>
