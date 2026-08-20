(function () {
	'use strict';

	const root = document.getElementById('app-content');
	if (!root || !window.AppointmentsUI) {
		return;
	}

	const UI = window.AppointmentsUI;
	const apiBase = root.dataset.apiBase.replace(/\/$/, '');
	const nodes = {
		onboarding: document.getElementById('appointments-onboarding'),
		onboardingForm: document.getElementById('appointments-onboarding-form'),
		onboardingName: document.getElementById('appointments-onboarding-name'),
		onboardingSlug: document.getElementById('appointments-onboarding-slug'),
		workspace: document.getElementById('appointments-workspace'),
		organization: document.getElementById('appointments-organization'),
		status: document.getElementById('appointments-status'),
		pageTitle: document.getElementById('appointments-page-title'),
		pageSubtitle: document.getElementById('appointments-page-subtitle'),
		newAppointment: document.getElementById('appointments-new'),
		calendar: document.getElementById('appointments-calendar'),
		periodLabel: document.getElementById('appointments-period-label'),
		search: document.getElementById('appointments-search'),
		filterStaff: document.getElementById('appointments-filter-staff'),
		filterLocation: document.getElementById('appointments-filter-location'),
		filterService: document.getElementById('appointments-filter-service'),
		filterStatus: document.getElementById('appointments-filter-status'),
		filterResource: document.getElementById('appointments-filter-resource'),
		appointmentDialog: document.getElementById('appointments-editor'),
		appointmentForm: document.getElementById('appointments-editor-form'),
		appointmentTitle: document.getElementById('appointments-editor-title'),
		appointmentSubmit: document.getElementById('appointments-editor-submit'),
		appointmentTimezone: document.getElementById('appointments-editor-timezone'),
		appointmentCustomFields: document.getElementById('appointments-editor-custom-fields'),
		appointmentCustomFieldControls: document.getElementById('appointments-editor-custom-field-controls'),
		configDialog: document.getElementById('appointments-config-editor'),
		configForm: document.getElementById('appointments-config-form'),
		configTitle: document.getElementById('appointments-config-title'),
		configFields: document.getElementById('appointments-config-fields'),
		availabilityForm: document.getElementById('appointments-availability-form'),
		availabilityType: document.getElementById('appointments-availability-type'),
		availabilitySubject: document.getElementById('appointments-availability-subject'),
		availabilityTimezone: document.getElementById('appointments-availability-timezone'),
		breakRows: document.getElementById('appointments-break-rows'),
		exceptionRows: document.getElementById('appointments-exception-rows'),
		settingsForm: document.getElementById('appointments-settings-form'),
		bookingPageLink: document.getElementById('appointments-booking-page-link'),
	};

	const state = {
		context: null,
		organization: null,
		catalog: {services: [], staff: [], locations: [], resources: [], availabilityRules: [], operations: [], failures: [], settings: {}},
		appointments: [],
		availabilityLoadId: 0,
		view: 'list',
		anchor: new Date(),
		section: 'calendar',
	};

	function showStatus(message, kind) {
		nodes.status.textContent = message || '';
		nodes.status.className = `appointments-status${kind ? ` is-${kind}` : ''}`;
	}

	function organizationApi(path) {
		return `${apiBase}/organizations/${encodeURIComponent(state.organization.id)}${path || ''}`;
	}

	function hasPermission(permission) {
		return UI.list(state.organization && state.organization.permissions).includes(permission);
	}

	function canManageAppointments() {
		return hasPermission('appointments.manage_appointments');
	}

	function canUpdateOwnAppointments() {
		return hasPermission('appointments.update_own');
	}

	function applyPermissions() {
		const allowedSections = {
			calendar: true,
			services: hasPermission('appointments.manage_catalog'),
			staff: hasPermission('appointments.manage_catalog'),
			locations: hasPermission('appointments.manage_catalog'),
			resources: hasPermission('appointments.manage_catalog'),
			availability: hasPermission('appointments.manage_availability') || hasPermission('appointments.manage_own_availability'),
			'booking-page': hasPermission('appointments.manage_settings'),
			operations: hasPermission('appointments.manage_settings'),
		};
		root.querySelectorAll('[data-section-target]').forEach(function (button) {
			button.hidden = !allowedSections[button.dataset.sectionTarget];
		});
		root.querySelectorAll('[data-section-panel]').forEach(function (panel) {
			if (!allowedSections[panel.dataset.sectionPanel]) {
				panel.hidden = true;
			}
		});
		const ownAvailabilityOnly = hasPermission('appointments.manage_own_availability') && !hasPermission('appointments.manage_availability');
		nodes.availabilityType.querySelectorAll('option').forEach(function (option) {
			option.hidden = ownAvailabilityOnly && option.value !== 'staff';
			option.disabled = ownAvailabilityOnly && option.value !== 'staff';
		});
		if (ownAvailabilityOnly) {
			nodes.availabilityType.value = 'staff';
		}
		if (!allowedSections[state.section]) {
			switchSection('calendar');
		}
		nodes.newAppointment.hidden = state.section !== 'calendar' || !canManageAppointments();
	}

	function entityName(entity, fallback) {
		if (!entity) {
			return fallback || UI.translate('Not assigned');
		}
		return entity.displayName || entity.name || entity.title || fallback || UI.translate('Unnamed');
	}

	function entityById(type, id) {
		return UI.list(state.catalog[type]).find((item) => String(item.id) === String(id));
	}

	function slugify(value) {
		return value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
			.replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80);
	}

	async function loadContext(preferredOrganizationId) {
		showStatus(UI.translate('Loading appointment module…'));
		try {
			const context = await UI.request(`${apiBase}/context`);
			state.context = Array.isArray(context) ? {organizations: context} : (context || {});
			const organizations = UI.list(state.context.organizations);
			if (!organizations.length) {
				nodes.workspace.hidden = true;
				nodes.onboarding.hidden = false;
				showStatus('');
				nodes.onboardingName.focus();
				return;
			}
			nodes.onboarding.hidden = true;
			nodes.workspace.hidden = false;
			UI.clear(nodes.organization);
			organizations.forEach(function (organization) {
				nodes.organization.appendChild(UI.option(organization.id, entityName(organization)));
			});
			const selectedId = preferredOrganizationId || state.context.currentOrganizationId || organizations[0].id;
			nodes.organization.value = String(selectedId);
			await selectOrganization(selectedId);
		} catch (error) {
			showStatus(UI.translate('The appointment module could not be loaded: {message}', {message: error.message}), 'error');
		}
	}

	async function createOrganization(event) {
		event.preventDefault();
		if (!nodes.onboardingForm.reportValidity()) {
			return;
		}
		const values = new FormData(nodes.onboardingForm);
		const submit = nodes.onboardingForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			const payload = await UI.request(`${apiBase}/organizations`, {
				method: 'POST',
				body: {
					name: String(values.get('name') || '').trim(),
					slug: String(values.get('slug') || '').trim(),
					timezone: String(values.get('timezone') || 'Europe/Berlin').trim(),
					locale: String(values.get('locale') || 'de'),
				},
			});
			await loadContext(payload && payload.organization ? payload.organization.id : null);
			showStatus(UI.translate('Organization created.'), 'success');
		} catch (error) {
			showStatus(UI.translate('The organization could not be created: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = false;
		}
	}

	function normalizeCatalog(payload) {
		const source = payload && payload.catalog ? payload.catalog : (payload || {});
		const operationPayload = source.operations && !Array.isArray(source.operations) ? source.operations : {};
		return {
			services: UI.list(source.services),
			staff: UI.list(source.staff),
			locations: UI.list(source.locations),
			resources: UI.list(source.resources),
			availabilityRules: UI.list(source.availabilityRules || source.availability),
			operations: UI.list(Array.isArray(source.operations) ? source.operations : operationPayload.items),
			failures: UI.list(source.failures || operationPayload.failures),
			settings: source.settings || source.organization || state.organization.settings || state.organization || {},
		};
	}

	async function selectOrganization(organizationId) {
		state.organization = UI.list(state.context.organizations).find((item) => String(item.id) === String(organizationId));
		if (!state.organization) {
			return;
		}
		nodes.organization.value = String(state.organization.id);
		showStatus(UI.translate('Loading organization…'));
		try {
			const payload = await UI.request(organizationApi('/catalog'));
			const catalogOrganization = payload && (payload.organization || (payload.catalog && payload.catalog.organization));
			if (catalogOrganization) {
				state.organization = Object.assign({}, state.organization, catalogOrganization);
			}
			state.catalog = normalizeCatalog(payload);
			const organizationToday = UI.dateKeyInTimeZone(new Date(), organizationTimezone()).split('-').map(Number);
			state.anchor = new Date(organizationToday[0], organizationToday[1] - 1, organizationToday[2]);
			applyPermissions();
			populateEntitySelectors();
			renderConfigurationLists();
			renderOperations();
			populateAvailabilitySubjects();
			populateSettings();
			await loadAppointments();
			showStatus('');
		} catch (error) {
			showStatus(UI.translate('Organization data could not be loaded: {message}', {message: error.message}), 'error');
		}
	}

	function resetSelect(select, firstLabel, items, selectedValue) {
		UI.clear(select);
		if (firstLabel !== null) {
			select.appendChild(UI.option('', firstLabel));
		}
		items.forEach(function (item) {
			select.appendChild(UI.option(item.id, entityName(item), String(item.id) === String(selectedValue || '')));
		});
	}

	function populateEntitySelectors() {
		resetSelect(nodes.filterStaff, UI.translate('All staff'), state.catalog.staff);
		resetSelect(nodes.filterLocation, UI.translate('All locations'), state.catalog.locations);
		resetSelect(nodes.filterService, UI.translate('All services'), state.catalog.services);
		resetSelect(nodes.filterResource, UI.translate('All resources'), state.catalog.resources);

		const form = nodes.appointmentForm.elements;
		resetSelect(form.serviceId, UI.translate('Select a service'), state.catalog.services);
		resetSelect(form.staffId, UI.translate('Select a staff member'), state.catalog.staff);
		resetSelect(form.locationId, UI.translate('No location'), state.catalog.locations);
	}

	function startOfWeek(date) {
		const result = new Date(date.getFullYear(), date.getMonth(), date.getDate());
		const day = result.getDay() || 7;
		result.setDate(result.getDate() - day + 1);
		return result;
	}

	function addDays(date, amount) {
		const result = new Date(date.getFullYear(), date.getMonth(), date.getDate());
		result.setDate(result.getDate() + amount);
		return result;
	}

	function visibleRange() {
		let from;
		let to;
		if (state.view === 'day') {
			from = new Date(state.anchor.getFullYear(), state.anchor.getMonth(), state.anchor.getDate());
			to = addDays(from, 1);
		} else if (state.view === 'week') {
			from = startOfWeek(state.anchor);
			to = addDays(from, 7);
		} else if (state.view === 'month') {
			from = startOfWeek(new Date(state.anchor.getFullYear(), state.anchor.getMonth(), 1));
			to = addDays(from, 42);
		} else {
			from = addDays(state.anchor, -30);
			to = addDays(state.anchor, 91);
		}
		return {from: from, to: to};
	}

	function queryParameters() {
		const range = visibleRange();
		const from = Math.floor(new Date(localDateTimeToIso(`${UI.dateKey(range.from)}T00:00`, organizationTimezone())).getTime() / 1000);
		const to = Math.floor(new Date(localDateTimeToIso(`${UI.dateKey(range.to)}T00:00`, organizationTimezone())).getTime() / 1000);
		const parameters = new URLSearchParams({from: String(from), to: String(to)});
		const filters = [
			['staffId', nodes.filterStaff.value],
			['locationId', nodes.filterLocation.value],
			['serviceId', nodes.filterService.value],
			['status', nodes.filterStatus.value],
			['resourceId', nodes.filterResource.value],
		];
		filters.forEach((entry) => { if (entry[1]) { parameters.set(entry[0], entry[1]); } });
		return parameters;
	}

	async function loadAppointments() {
		if (!state.organization) {
			return;
		}
		nodes.calendar.setAttribute('aria-busy', 'true');
		UI.clear(nodes.calendar).appendChild(UI.element('p', {className: 'appointments-empty', text: UI.translate('Loading appointments…')}));
		try {
			const parameters = queryParameters();
			const search = nodes.search.value.trim();
			const payload = search
				? await UI.request(`${organizationApi('/appointments')}/search`, {
					method: 'POST', body: Object.assign(Object.fromEntries(parameters.entries()), {search: search}),
				})
				: await UI.request(`${organizationApi('/appointments')}?${parameters.toString()}`);
			state.appointments = UI.list(payload && (payload.appointments || payload.items || payload));
			renderCalendar();
		} catch (error) {
			UI.clear(nodes.calendar).appendChild(UI.element('p', {className: 'appointments-error', text: UI.translate('Appointments could not be loaded: {message}', {message: error.message})}));
		} finally {
			nodes.calendar.setAttribute('aria-busy', 'false');
		}
	}

	function appointmentStart(appointment) {
		return appointment.startsAt || appointment.startAt || appointment.start || '';
	}

	function appointmentContact(appointment) {
		return appointment.contact || appointment.customer || {};
	}

	function appointmentPerson(appointment) {
		const contact = appointmentContact(appointment);
		const name = `${contact.firstName || appointment.firstName || ''} ${contact.lastName || appointment.lastName || ''}`.trim();
		return name || UI.translate('Unnamed customer');
	}

	function appointmentRelatedName(appointment, type, idKey) {
		const collection = ({service: 'services', location: 'locations', resource: 'resources'})[type] || type;
		return entityName(appointment[type] || entityById(collection, appointment[idKey]));
	}

	function appointmentCard(appointment, compact) {
		const start = appointmentStart(appointment);
		const status = appointment.status || 'pending';
		const card = UI.element('article', {className: `appointments-appointment state-${status}`});
		const service = appointment.service || entityById('services', appointment.serviceId);
		if (service && /^#[0-9a-f]{6}$/i.test(service.color || '')) {
			card.style.setProperty('--appointment-color', service.color);
		}
		const heading = UI.element('div', {className: 'appointments-appointment-heading'}, [
			UI.element('div', {}, [
				UI.element('h4', {text: appointmentPerson(appointment)}),
				UI.element('p', {className: 'appointments-appointment-service', text: appointmentRelatedName(appointment, 'service', 'serviceId')}),
			]),
			UI.element('span', {className: `appointments-state state-${status}`, text: UI.statusLabel(status)}),
		]);
		card.appendChild(heading);
		const details = UI.element('dl', {className: 'appointments-compact-details'});
		[
			[UI.translate('Time'), `${UI.formatDate(start, organizationTimezone())}, ${UI.formatTime(start, organizationTimezone())}`],
			[UI.translate('Staff'), appointmentRelatedName(appointment, 'staff', 'staffId')],
			[UI.translate('Location'), appointmentRelatedName(appointment, 'location', 'locationId')],
			[UI.translate('Booking number'), appointment.bookingNumber || '—'],
		].forEach(function (entry) {
			if (compact && (entry[0] === UI.translate('Location') || entry[0] === UI.translate('Booking number'))) {
				return;
			}
			details.appendChild(UI.element('dt', {text: entry[0]}));
			details.appendChild(UI.element('dd', {text: entry[1]}));
		});
		card.appendChild(details);
		if (appointment.hasConflict || UI.list(appointment.conflicts).length) {
			card.appendChild(UI.element('p', {className: 'appointments-conflict', role: 'alert', text: UI.translate('Conflict detected for this appointment.')}));
		}
		const actions = UI.element('div', {className: 'appointments-card-actions'});
		const active = ['pending', 'confirmed', 'rescheduled'].includes(status);
		if ((canManageAppointments() && active) || canUpdateOwnAppointments()) {
			actions.appendChild(UI.element('button', {type: 'button', text: canManageAppointments() ? UI.translate('Edit') : UI.translate('Edit internal note'), onclick: (event) => openAppointmentEditor(appointment, event.currentTarget)}));
		}
		if ((canManageAppointments() || canUpdateOwnAppointments()) && (status === 'pending' || status === 'rescheduled')) {
			actions.appendChild(statusButton(appointment, 'confirmed', UI.translate('Confirm')));
		}
		if ((canManageAppointments() || canUpdateOwnAppointments()) && (status === 'confirmed' || status === 'rescheduled')) {
			actions.appendChild(statusButton(appointment, 'completed', UI.translate('Mark completed')));
			actions.appendChild(statusButton(appointment, 'no_show', UI.translate('Mark no-show')));
		}
		if ((canManageAppointments() || canUpdateOwnAppointments()) && active) {
			actions.appendChild(statusButton(appointment, 'cancelled_by_staff', UI.translate('Cancel appointment'), true));
		}
		if (actions.childElementCount) {
			card.appendChild(actions);
		}
		return card;
	}

	function statusButton(appointment, status, label, destructive) {
		return UI.element('button', {
			type: 'button',
			text: label,
			className: destructive ? 'appointments-danger-subtle' : '',
			onclick: function (event) { updateAppointmentStatus(appointment, status, event.currentTarget); },
		});
	}

	async function updateAppointmentStatus(appointment, status, button) {
		if (status === 'cancelled_by_staff' && !window.confirm(UI.translate('Cancel this appointment and release its slot?'))) {
			return;
		}
		button.disabled = true;
		try {
			await UI.request(`${organizationApi('/appointments')}/${encodeURIComponent(appointment.id)}/status`, {method: 'POST', body: {status: status}});
			showStatus(UI.translate('Appointment status updated.'), 'success');
			await loadAppointments();
		} catch (error) {
			showStatus(UI.translate('The status could not be updated: {message}', {message: error.message}), 'error');
			button.disabled = false;
		}
	}

	function zonedDateKey(value) {
		return UI.dateKeyInTimeZone(value, organizationTimezone());
	}

	function appointmentsByDate() {
		const grouped = new Map();
		state.appointments.forEach(function (appointment) {
			const key = zonedDateKey(appointmentStart(appointment));
			if (!grouped.has(key)) {
				grouped.set(key, []);
			}
			grouped.get(key).push(appointment);
		});
		grouped.forEach((items) => items.sort((left, right) => String(appointmentStart(left)).localeCompare(String(appointmentStart(right)))));
		return grouped;
	}

	function renderCalendar() {
		UI.clear(nodes.calendar);
		setPeriodLabel();
		if (!state.appointments.length) {
			const empty = UI.element('div', {className: 'appointments-empty-state'}, [
				UI.element('h3', {text: UI.translate('No appointments found')}),
				UI.element('p', {text: UI.translate('Try another date or clear the filters.')}),
			]);
			if (canManageAppointments()) {
				empty.appendChild(UI.element('button', {type: 'button', className: 'primary', text: UI.translate('Create appointment'), onclick: (event) => openAppointmentEditor(null, event.currentTarget)}));
			}
			nodes.calendar.appendChild(empty);
			return;
		}
		if (state.view === 'list') {
			const list = UI.element('div', {className: 'appointments-list'});
			state.appointments.slice().sort((a, b) => String(appointmentStart(a)).localeCompare(String(appointmentStart(b))))
				.forEach((appointment) => list.appendChild(appointmentCard(appointment, false)));
			nodes.calendar.appendChild(list);
			return;
		}
		const grouped = appointmentsByDate();
		const range = visibleRange();
		const days = state.view === 'day' ? 1 : (state.view === 'week' ? 7 : 42);
		const grid = UI.element('div', {className: `appointments-calendar-grid is-${state.view}`});
		for (let index = 0; index < days; index += 1) {
			const date = addDays(range.from, index);
			const key = UI.dateKey(date);
			const day = UI.element('section', {className: 'appointments-calendar-day'});
			day.appendChild(UI.element('h3', {text: new Intl.DateTimeFormat(UI.locale(), {weekday: 'short', day: 'numeric', month: state.view === 'month' ? 'short' : 'long'}).format(date)}));
			const items = grouped.get(key) || [];
			if (!items.length) {
				day.appendChild(UI.element('p', {className: 'appointments-day-empty', text: UI.translate('No appointments')}));
			} else {
				items.forEach((appointment) => day.appendChild(appointmentCard(appointment, state.view === 'month')));
			}
			grid.appendChild(day);
		}
		nodes.calendar.appendChild(grid);
	}

	function setPeriodLabel() {
		const range = visibleRange();
		if (state.view === 'list') {
			nodes.periodLabel.textContent = UI.translate('Upcoming appointments');
		} else if (state.view === 'day') {
			nodes.periodLabel.textContent = new Intl.DateTimeFormat(UI.locale(), {dateStyle: 'full'}).format(state.anchor);
		} else if (state.view === 'week') {
			nodes.periodLabel.textContent = UI.translate('{start} – {end}', {
				start: new Intl.DateTimeFormat(UI.locale(), {day: 'numeric', month: 'short'}).format(range.from),
				end: new Intl.DateTimeFormat(UI.locale(), {day: 'numeric', month: 'short', year: 'numeric'}).format(addDays(range.to, -1)),
			});
		} else {
			nodes.periodLabel.textContent = new Intl.DateTimeFormat(UI.locale(), {month: 'long', year: 'numeric'}).format(state.anchor);
		}
	}

	function movePeriod(direction) {
		if (state.view === 'month') {
			state.anchor = new Date(state.anchor.getFullYear(), state.anchor.getMonth() + direction, 1);
		} else {
			const amount = state.view === 'week' ? 7 : (state.view === 'list' ? 30 : 1);
			state.anchor = addDays(state.anchor, amount * direction);
		}
		loadAppointments();
	}

	function organizationTimezone() {
		return state.catalog.settings.timezone || state.organization.timezone || 'Europe/Berlin';
	}

	function organizationToday() {
		const parts = UI.dateKeyInTimeZone(new Date(), organizationTimezone()).split('-').map(Number);
		return new Date(parts[0], parts[1] - 1, parts[2]);
	}

	function dateTimeInputValue(value, timeZone) {
		const normalized = typeof value === 'number' && value < 100000000000 ? value * 1000 : value;
		const date = new Date(normalized);
		if (Number.isNaN(date.getTime())) {
			return '';
		}
		const parts = new Intl.DateTimeFormat('en-CA', {
			timeZone: timeZone || organizationTimezone(), year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
		}).formatToParts(date);
		const fields = Object.fromEntries(parts.map((part) => [part.type, part.value]));
		return `${fields.year}-${fields.month}-${fields.day}T${fields.hour}:${fields.minute}`;
	}

	function localDateTimeToIso(value, timeZone) {
		const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value || '');
		if (!match) {
			return '';
		}
		const desired = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]));
		const formatter = new Intl.DateTimeFormat('en-CA', {
			timeZone: timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
		});
		const localParts = (timestamp) => {
			const parts = formatter.formatToParts(new Date(timestamp));
			return Object.fromEntries(parts.map((part) => [part.type, part.value]));
		};
		const offsets = new Set();
		[-172800000, -86400000, 0, 86400000, 172800000].forEach((delta) => {
			const probe = desired + delta;
			const observed = localParts(probe);
			const observedWallTime = Date.UTC(Number(observed.year), Number(observed.month) - 1, Number(observed.day), Number(observed.hour), Number(observed.minute));
			offsets.add(observedWallTime - probe);
		});
		const candidates = Array.from(offsets)
			.map((offset) => desired - offset)
			.filter((candidate) => {
				const roundTrip = localParts(candidate);
				return `${roundTrip.year}-${roundTrip.month}-${roundTrip.day}T${roundTrip.hour}:${roundTrip.minute}` === value;
			});
		const uniqueCandidates = Array.from(new Set(candidates));
		if (uniqueCandidates.length === 0) {
			throw new Error(UI.translate('The local time {time} does not exist in {timezone}.', {time: value, timezone: timeZone}));
		}
		if (uniqueCandidates.length > 1) {
			throw new Error(UI.translate('The local time {time} occurs twice in {timezone}. Choose another time.', {time: value, timezone: timeZone}));
		}
		return new Date(uniqueCandidates[0]).toISOString();
	}

	function timeToMinute(value) {
		const parts = String(value || '00:00').split(':');
		return (Number(parts[0]) * 60) + Number(parts[1]);
	}

	function minuteToTime(value, fallback) {
		const minute = Number(value);
		if (!Number.isFinite(minute)) {
			return fallback;
		}
		return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
	}

	function appointmentCustomFieldControl(field, answerValue) {
		const type = field.type || 'text';
		const validation = field.validation || {};
		const name = `formAnswer-${field.id}`;
		let input;
		if (type === 'textarea') {
			input = UI.element('textarea', {
				name: name, rows: 4, required: field.required,
				minLength: validation.min, maxLength: validation.max || 5000,
			});
		} else if (type === 'select' || type === 'multi_select') {
			input = UI.element('select', {name: name, required: field.required, multiple: type === 'multi_select'});
			if (type === 'select' && !field.required) {
				input.appendChild(UI.option('', UI.translate('Select an option')));
			}
			UI.list(validation.options).forEach(function (optionValue) {
				input.appendChild(UI.option(
					optionValue.value !== undefined ? optionValue.value : optionValue,
					optionValue.label || optionValue,
				));
			});
		} else if (type === 'checkbox') {
			input = UI.element('input', {name: name, type: 'checkbox', required: field.required});
		} else if (type === 'boolean') {
			input = UI.element('select', {name: name, required: field.required}, [
				UI.option('', UI.translate('Select an option')),
				UI.option('true', UI.translate('Yes')),
				UI.option('false', UI.translate('No')),
			]);
		} else {
			const inputType = ({phone: 'tel', email: 'email', number: 'number', date: 'date'})[type] || 'text';
			input = UI.element('input', {
				name: name, type: inputType, required: field.required,
				min: type === 'number' ? validation.min : null,
				max: type === 'number' ? validation.max : null,
				minLength: type === 'text' || type === 'phone' || type === 'email' ? validation.min : null,
				maxLength: type === 'text' || type === 'phone' || type === 'email' ? (validation.max || 512) : null,
			});
		}
		if (type === 'checkbox') {
			input.checked = Boolean(answerValue);
		} else if (type === 'multi_select') {
			const selectedValues = new Set(UI.list(answerValue).map(String));
			Array.from(input.options).forEach((option) => { option.selected = selectedValues.has(option.value); });
		} else if (type === 'boolean') {
			input.value = answerValue === true ? 'true' : (answerValue === false ? 'false' : '');
		} else if (answerValue !== undefined && answerValue !== null) {
			input.value = String(answerValue);
		}
		const label = UI.element('label', {className: type === 'checkbox' ? 'appointments-inline-check' : ''});
		if (type === 'checkbox') {
			label.appendChild(input);
			label.appendChild(document.createTextNode(` ${field.label}`));
		} else {
			label.appendChild(document.createTextNode(field.label));
			label.appendChild(input);
		}
		if (field.helpText) {
			label.appendChild(UI.element('small', {className: 'appointments-help', text: field.helpText}));
		}
		return label;
	}

	function renderAppointmentCustomFields(existingAnswers) {
		UI.clear(nodes.appointmentCustomFieldControls);
		const form = nodes.appointmentForm.elements;
		const service = entityById('services', form.serviceId.value);
		form.phone.required = Boolean(service && service.phoneRequired);
		const answersByField = UI.list(existingAnswers).reduce(function (answers, answer) {
			answers[String(answer.fieldId)] = answer.value;
			return answers;
		}, {});
		const fields = UI.list(service && service.formFields)
			.slice().sort((left, right) => Number(left.order || 0) - Number(right.order || 0));
		nodes.appointmentCustomFields.hidden = fields.length === 0;
		fields.forEach((field) => nodes.appointmentCustomFieldControls.appendChild(
			appointmentCustomFieldControl(field, answersByField[String(field.id)]),
		));
	}

	function appointmentFormAnswers() {
		const service = entityById('services', nodes.appointmentForm.elements.serviceId.value);
		return UI.list(service && service.formFields).reduce(function (answers, field) {
			const control = nodes.appointmentForm.elements[`formAnswer-${field.id}`];
			let value;
			if (!control) {
				return answers;
			}
			if (control instanceof RadioNodeList) {
				value = control.value;
			} else if (control.type === 'checkbox') {
				value = control.checked;
			} else if (field.type === 'boolean') {
				value = control.value === '' ? null : control.value === 'true';
			} else if (control.multiple) {
				value = Array.from(control.selectedOptions).map((option) => option.value);
			} else {
				value = control.value;
			}
			const empty = value === null || value === '' || (field.type === 'checkbox' && value === false) || (Array.isArray(value) && value.length === 0);
			if (field.required || !empty) {
				answers[field.id] = value;
			}
			return answers;
		}, {});
	}

	function openAppointmentEditor(appointment, opener) {
		nodes.appointmentForm.reset();
		populateEntitySelectors();
		const form = nodes.appointmentForm.elements;
		form.appointmentId.value = appointment ? appointment.id : '';
		form.status.querySelectorAll('option').forEach(function (option) {
			const allowedForCreate = option.value === 'pending' || option.value === 'confirmed';
			option.hidden = !appointment && !allowedForCreate;
			option.disabled = !appointment && !allowedForCreate;
		});
		const ownNoteOnly = Boolean(appointment) && !canManageAppointments() && canUpdateOwnAppointments();
		nodes.appointmentTitle.textContent = ownNoteOnly ? UI.translate('Edit internal note') : (appointment ? UI.translate('Edit appointment') : UI.translate('New appointment'));
		nodes.appointmentSubmit.textContent = ownNoteOnly ? UI.translate('Save internal note') : UI.translate('Save appointment');
		nodes.appointmentForm.querySelectorAll('[data-appointment-full-fields]').forEach(function (node) {
			node.hidden = ownNoteOnly;
			node.querySelectorAll('input, select, textarea').forEach((control) => { control.disabled = ownNoteOnly; });
		});
		nodes.appointmentTimezone.textContent = UI.translate('Times are entered in {timezone}.', {timezone: organizationTimezone()});
		if (appointment) {
			const contact = appointmentContact(appointment);
			form.firstName.value = contact.firstName || appointment.firstName || '';
			form.lastName.value = contact.lastName || appointment.lastName || '';
			form.email.value = contact.email || appointment.email || '';
			form.phone.value = contact.phone || appointment.phone || '';
			form.serviceId.value = appointment.serviceId || (appointment.service && appointment.service.id) || '';
			form.staffId.value = appointment.staffId || (appointment.staff && appointment.staff.id) || '';
			form.locationId.value = appointment.locationId || (appointment.location && appointment.location.id) || '';
			form.startsAtLocal.value = dateTimeInputValue(appointmentStart(appointment));
			form.status.value = appointment.status || 'pending';
			form.status.disabled = true;
			form.customerNote.value = appointment.customerNote || appointment.note || '';
			form.internalNote.value = appointment.internalNote || '';
		} else {
			form.status.disabled = false;
			const nextHour = new Date();
			nextHour.setHours(nextHour.getHours() + 1, 0, 0, 0);
			form.startsAtLocal.value = dateTimeInputValue(nextHour);
		}
		renderAppointmentCustomFields(appointment && appointment.formAnswers);
		UI.showDialog(nodes.appointmentDialog, opener);
	}

	async function saveAppointment(event) {
		event.preventDefault();
		if (!nodes.appointmentForm.reportValidity()) {
			return;
		}
		const values = new FormData(nodes.appointmentForm);
		const appointmentId = String(values.get('appointmentId') || '');
		if (appointmentId && !canManageAppointments() && canUpdateOwnAppointments()) {
			const submit = nodes.appointmentForm.querySelector('button[type="submit"]');
			submit.disabled = true;
			try {
				await UI.request(`${organizationApi('/appointments')}/${encodeURIComponent(appointmentId)}`, {
					method: 'PUT', body: {internalNote: String(values.get('internalNote') || '').trim()},
				});
				UI.closeDialog(nodes.appointmentDialog);
				showStatus(UI.translate('Internal note saved.'), 'success');
				await loadAppointments();
			} catch (error) {
				showStatus(UI.translate('The internal note could not be saved: {message}', {message: error.message}), 'error');
			} finally {
				submit.disabled = false;
			}
			return;
		}
		let startsAt;
		try {
			startsAt = localDateTimeToIso(String(values.get('startsAtLocal') || ''), organizationTimezone());
		} catch (error) {
			showStatus(error.message, 'error');
			return;
		}
		const payload = {
			serviceId: String(values.get('serviceId') || ''),
			staffId: String(values.get('staffId') || ''),
			locationId: String(values.get('locationId') || '') || null,
			startsAt: startsAt,
			timezone: organizationTimezone(),
			contact: {
				firstName: String(values.get('firstName') || '').trim(),
				lastName: String(values.get('lastName') || '').trim(),
				email: String(values.get('email') || '').trim(),
				phone: String(values.get('phone') || '').trim(),
			},
			customerNote: String(values.get('customerNote') || '').trim(),
			internalNote: String(values.get('internalNote') || '').trim(),
		};
		payload.formAnswers = appointmentFormAnswers();
		if (!appointmentId) {
			payload.status = String(values.get('status') || 'pending');
		}
		const submit = nodes.appointmentForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			await UI.request(appointmentId ? `${organizationApi('/appointments')}/${encodeURIComponent(appointmentId)}` : organizationApi('/appointments'), {
				method: appointmentId ? 'PUT' : 'POST', body: payload,
			});
			UI.closeDialog(nodes.appointmentDialog);
			showStatus(appointmentId ? UI.translate('Appointment updated.') : UI.translate('Appointment created.'), 'success');
			await loadAppointments();
		} catch (error) {
			showStatus(UI.translate('The appointment could not be saved: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = false;
		}
	}

	function optionList(items) {
		return items.map((item) => ({value: item.id, label: entityName(item)}));
	}

	function configurationDefinitions() {
		return {
			services: {
				singular: UI.translate('Service'),
				fields: [
					{name: 'name', label: UI.translate('Name'), required: true},
					{name: 'shortName', label: UI.translate('Internal short name'), required: true},
					{name: 'slug', label: UI.translate('Direct-link address'), required: true},
					{name: 'description', label: UI.translate('Description'), type: 'textarea'},
					{name: 'durationMinutes', label: UI.translate('Duration in minutes'), type: 'number', min: 5, max: 1440, value: 30, required: true},
					{name: 'bufferBeforeMinutes', label: UI.translate('Buffer before in minutes'), type: 'number', min: 0, max: 1440, value: 0},
					{name: 'bufferAfterMinutes', label: UI.translate('Buffer after in minutes'), type: 'number', min: 0, max: 1440, value: 0},
					{name: 'priceMin', label: UI.translate('Price from'), type: 'number', min: 0, step: '0.01', nullable: true},
					{name: 'priceMax', label: UI.translate('Price to'), type: 'number', min: 0, step: '0.01', nullable: true},
					{name: 'currency', label: UI.translate('Currency'), value: 'EUR'},
					{name: 'confirmationMode', label: UI.translate('Booking mode'), type: 'select', required: true, options: [
						{value: 'automatic', label: UI.translate('Confirm automatically')},
						{value: 'manual', label: UI.translate('Require manual confirmation')},
					]},
					{name: 'visibility', label: UI.translate('Visibility'), type: 'select', required: true, options: [
						{value: 'public', label: UI.translate('Public')}, {value: 'direct_link', label: UI.translate('Direct link only')}, {value: 'internal', label: UI.translate('Internal only')},
					]},
					{name: 'appointmentType', label: UI.translate('Appointment type'), type: 'select', required: true, options: appointmentTypeOptions},
					{name: 'minimumNoticeMinutes', label: UI.translate('Minimum notice in minutes'), type: 'number', min: 0, max: 525600, value: 60},
					{name: 'maximumHorizonDays', label: UI.translate('Maximum booking horizon in days'), type: 'number', min: 1, max: 730, value: 90},
					{name: 'cancellationNoticeMinutes', label: UI.translate('Cancellation deadline in minutes'), type: 'number', min: 0, max: 525600, value: 1440},
					{name: 'rescheduleNoticeMinutes', label: UI.translate('Rescheduling deadline in minutes'), type: 'number', min: 0, max: 525600, value: 1440},
					{name: 'staffIds', label: UI.translate('Allowed staff'), type: 'multiselect', options: () => optionList(state.catalog.staff)},
					{name: 'locationIds', label: UI.translate('Allowed locations'), type: 'multiselect', options: () => optionList(state.catalog.locations)},
					{name: 'resourceRequirements', label: UI.translate('Required resources'), type: 'resourceRequirements'},
					{name: 'color', label: UI.translate('Calendar color'), type: 'color', value: '#00679e'},
					{name: 'bookingNotes', label: UI.translate('Booking instructions'), type: 'textarea'},
					{name: 'preparation', label: UI.translate('Preparation information'), type: 'textarea'},
					{name: 'phoneRequired', label: UI.translate('Require phone number'), type: 'checkbox'},
					{name: 'formFields', label: UI.translate('Custom booking fields'), type: 'formFields'},
					{name: 'active', label: UI.translate('Active'), type: 'checkbox', value: true},
				],
			},
			staff: {
				singular: UI.translate('Staff member'),
				fields: [
					{
						name: 'userUid', label: UI.translate('Office user'),
						type: UI.list(state.context.users).length ? 'select' : 'text',
						options: () => UI.list(state.context.users).map((user) => ({value: user.uid || user.id, label: entityName(user)})),
						helpText: UI.list(state.context.users).length ? '' : UI.translate('Enter the exact Nextcloud user ID. The server verifies that it exists.'),
					},
					{name: 'displayName', label: UI.translate('Display name'), required: true},
					{name: 'slug', label: UI.translate('Direct-link address'), required: true},
					{name: 'description', label: UI.translate('Short description'), type: 'textarea'},
					{name: 'qualifications', label: UI.translate('Qualifications and specialties'), type: 'textarea'},
					{name: 'locationIds', label: UI.translate('Allowed locations'), type: 'multiselect', options: () => optionList(state.catalog.locations)},
					{name: 'timezone', label: UI.translate('Time zone'), value: 'Europe/Berlin'},
					{name: 'calendarUri', label: UI.translate('Calendar identifier')},
					{name: 'publicBooking', label: UI.translate('Publicly bookable'), type: 'checkbox', value: true},
					{name: 'active', label: UI.translate('Active'), type: 'checkbox', value: true},
				],
			},
			locations: {
				singular: UI.translate('Location'),
				fields: [
					{name: 'name', label: UI.translate('Name'), required: true},
					{name: 'slug', label: UI.translate('Direct-link address'), required: true},
					{name: 'kind', label: UI.translate('Appointment type'), type: 'select', required: true, options: appointmentTypeOptions},
					{name: 'address', label: UI.translate('Address')},
					{name: 'room', label: UI.translate('Room or additional information')},
					{name: 'timezone', label: UI.translate('Time zone'), value: 'Europe/Berlin'},
					{name: 'publicNotes', label: UI.translate('Public notes'), type: 'textarea'},
					{name: 'directions', label: UI.translate('Directions'), type: 'textarea'},
					{name: 'accessibility', label: UI.translate('Accessibility information'), type: 'textarea'},
					{name: 'active', label: UI.translate('Active'), type: 'checkbox', value: true},
				],
			},
			resources: {
				singular: UI.translate('Resource'),
				fields: [
					{name: 'name', label: UI.translate('Name'), required: true},
					{name: 'type', label: UI.translate('Resource type'), required: true},
					{name: 'locationId', label: UI.translate('Location'), type: 'select', options: () => optionList(state.catalog.locations)},
					{name: 'capacity', label: UI.translate('Capacity'), type: 'number', min: 1, max: 100, value: 1, required: true},
					{name: 'active', label: UI.translate('Active'), type: 'checkbox', value: true},
				],
			},
		};
	}

	function appointmentTypeOptions() {
		return [
			{value: 'on_site', label: UI.translate('On-site appointment')},
			{value: 'phone', label: UI.translate('Phone appointment')},
			{value: 'video', label: UI.translate('Video appointment')},
			{value: 'customer_site', label: UI.translate('Appointment at customer location')},
			{value: 'custom', label: UI.translate('Custom appointment type')},
		];
	}

	function resolveFieldOptions(field) {
		const options = typeof field.options === 'function' ? field.options() : field.options;
		return UI.list(options);
	}

	function createConfigurationField(field, record) {
		const current = record && record[field.name] !== undefined ? record[field.name] : field.value;
		if (field.type === 'formFields') {
			return createFormFieldsEditor(field, record && (record.formFields || record.bookingFields));
		}
		if (field.type === 'resourceRequirements') {
			return createResourceRequirementsEditor(field, record && record.resourceRequirements);
		}
		const label = UI.element('label', {className: field.type === 'checkbox' ? 'appointments-inline-check appointments-config-check' : ''});
		let input;
		if (field.type === 'textarea') {
			input = UI.element('textarea', {name: field.name, rows: 3, maxlength: 4000});
			input.value = current || '';
		} else if (field.type === 'select' || field.type === 'multiselect') {
			input = UI.element('select', {name: field.name, multiple: field.type === 'multiselect', required: field.required});
			if (field.type === 'select' && !field.required) {
				input.appendChild(UI.option('', UI.translate('Not assigned')));
			}
			const selectedValues = new Set(Array.isArray(current) ? current.map(String) : [String(current || '')]);
			resolveFieldOptions(field).forEach((item) => input.appendChild(UI.option(item.value, item.label, selectedValues.has(String(item.value)))));
		} else {
			input = UI.element('input', {
				name: field.name,
				type: field.type || 'text',
				required: field.required,
				min: field.min,
				max: field.max,
				step: field.step,
				checked: field.type === 'checkbox' ? Boolean(current) : false,
			});
			if (field.type !== 'checkbox') {
				input.value = current === undefined || current === null ? '' : current;
			}
		}
		if (field.type === 'checkbox') {
			label.appendChild(input);
			label.appendChild(document.createTextNode(` ${field.label}`));
		} else {
			label.appendChild(document.createTextNode(field.label));
			label.appendChild(input);
		}
		if (field.helpText) {
			label.appendChild(UI.element('small', {className: 'appointments-help', text: field.helpText}));
		}
		return label;
	}

	function createResourceRequirementsEditor(field, requirements) {
		const wrapper = UI.element('fieldset', {className: 'appointments-form-fields-editor appointments-resource-requirements'});
		wrapper.appendChild(UI.element('legend', {text: field.label}));
		const byResource = new Map(UI.list(requirements).map((item) => [String(item.resourceId), item]));
		if (!state.catalog.resources.length) {
			wrapper.appendChild(UI.element('p', {className: 'appointments-help', text: UI.translate('Create resources before assigning them to a service.')}));
			return wrapper;
		}
		state.catalog.resources.forEach(function (resource) {
			const current = byResource.get(String(resource.id));
			const row = UI.element('div', {className: 'appointments-resource-requirement', dataset: {resourceRequirement: resource.id}});
			const enabled = UI.element('input', {type: 'checkbox', name: 'resourceRequirementEnabled', checked: Boolean(current)});
			const quantity = UI.element('input', {type: 'number', name: 'resourceRequirementQuantity', min: 1, max: 100, value: current ? current.quantity : 1, disabled: !current});
			enabled.addEventListener('change', () => { quantity.disabled = !enabled.checked; });
			row.appendChild(UI.element('label', {className: 'appointments-inline-check'}, [enabled, entityName(resource)]));
			row.appendChild(UI.element('label', {}, [UI.translate('Quantity'), quantity]));
			wrapper.appendChild(row);
		});
		return wrapper;
	}

	function extractResourceRequirements() {
		return Array.from(nodes.configFields.querySelectorAll('[data-resource-requirement]')).filter(function (row) {
			return row.querySelector('[name="resourceRequirementEnabled"]').checked;
		}).map(function (row) {
			return {resourceId: row.dataset.resourceRequirement, quantity: Number(row.querySelector('[name="resourceRequirementQuantity"]').value || 1)};
		});
	}

	function formFieldTypeOptions(selected) {
		return [
			['text', UI.translate('Single-line text')], ['textarea', UI.translate('Multi-line text')],
			['select', UI.translate('Selection')], ['multi_select', UI.translate('Multiple selection')],
			['checkbox', UI.translate('Checkbox')], ['boolean', UI.translate('Yes or no')],
			['phone', UI.translate('Phone')], ['email', UI.translate('Email')],
			['number', UI.translate('Number')], ['date', UI.translate('Date')],
		].map((entry) => UI.option(entry[0], entry[1], entry[0] === selected));
	}

	function formFieldRow(field) {
		const row = UI.element('div', {className: 'appointments-custom-field-row', dataset: {formFieldRow: 'true'}});
		row.dataset.originalType = field.type || 'text';
		row.appointmentsValidation = Object.assign({}, field.validation || {});
		if (field.id) {
			row.dataset.fieldId = field.id;
		}
		const type = UI.element('select', {name: 'formFieldType'}, formFieldTypeOptions(field.type || 'text'));
		const label = UI.element('input', {name: 'formFieldLabel', type: 'text', value: field.label || '', required: true, maxlength: 255});
		const help = UI.element('input', {name: 'formFieldHelp', type: 'text', value: field.helpText || '', maxlength: 1000});
		const required = UI.element('input', {name: 'formFieldRequired', type: 'checkbox', checked: Boolean(field.required)});
		const visibility = UI.element('select', {name: 'formFieldVisibility'}, [
			UI.option('public', UI.translate('Public'), field.visibility !== 'internal'),
			UI.option('internal', UI.translate('Internal only'), field.visibility === 'internal'),
		]);
		const order = UI.element('input', {name: 'formFieldOrder', type: 'number', min: 0, value: Number(field.order || 0)});
		const optionValues = UI.list(field.validation && field.validation.options).map((item) => item.value !== undefined ? item.value : item).join(', ');
		const options = UI.element('input', {name: 'formFieldOptions', type: 'text', value: optionValues, maxlength: 5000, placeholder: UI.translate('Option one, option two')});
		const optionsLabel = UI.element('label', {className: 'appointments-custom-field-options'}, [UI.translate('Options (comma-separated)'), options]);
		const synchronizeOptions = function () {
			const supportsOptions = type.value === 'select' || type.value === 'multi_select';
			optionsLabel.hidden = !supportsOptions;
			options.disabled = !supportsOptions;
		};
		type.addEventListener('change', synchronizeOptions);
		synchronizeOptions();
		row.appendChild(UI.element('label', {}, [UI.translate('Type'), type]));
		row.appendChild(UI.element('label', {}, [UI.translate('Label'), label]));
		row.appendChild(UI.element('label', {}, [UI.translate('Help text'), help]));
		row.appendChild(UI.element('label', {className: 'appointments-inline-check'}, [required, UI.translate('Required')]));
		row.appendChild(UI.element('label', {}, [UI.translate('Visibility'), visibility]));
		row.appendChild(UI.element('label', {}, [UI.translate('Order'), order]));
		row.appendChild(optionsLabel);
		row.appendChild(UI.element('button', {
			type: 'button', className: 'appointments-danger-subtle', text: UI.translate('Remove field'),
			onclick: function () { row.remove(); },
		}));
		return row;
	}

	function createFormFieldsEditor(field, existingFields) {
		const wrapper = UI.element('fieldset', {className: 'appointments-form-fields-editor'});
		wrapper.appendChild(UI.element('legend', {text: field.label}));
		wrapper.appendChild(UI.element('p', {className: 'appointments-help', text: UI.translate('Ask only for information needed to provide the service. HTML is not supported.')}));
		const rows = UI.element('div', {className: 'appointments-custom-field-rows'});
		UI.list(existingFields).sort((a, b) => Number(a.order || 0) - Number(b.order || 0)).forEach((item) => rows.appendChild(formFieldRow(item)));
		wrapper.appendChild(rows);
		wrapper.appendChild(UI.element('button', {
			type: 'button', text: UI.translate('Add field'), onclick: () => rows.appendChild(formFieldRow({order: rows.childElementCount})),
		}));
		return wrapper;
	}

	function extractFormFields() {
		return Array.from(nodes.configFields.querySelectorAll('[data-form-field-row]')).map(function (row, index) {
			const type = row.querySelector('[name="formFieldType"]').value;
			const optionsInput = row.querySelector('[name="formFieldOptions"]');
			const optionValues = optionsInput.disabled ? [] : optionsInput.value.split(',').map((value) => value.trim()).filter(Boolean);
			if ((type === 'select' || type === 'multi_select') && !optionValues.length) {
				throw new Error(UI.translate('Selection fields need at least one option.'));
			}
			const validation = row.dataset.originalType === type ? Object.assign({}, row.appointmentsValidation || {}) : {};
			delete validation.options;
			if (optionValues.length) {
				validation.options = optionValues;
			}
			return {
				id: row.dataset.fieldId || undefined,
				type: type,
				label: row.querySelector('[name="formFieldLabel"]').value.trim(),
				helpText: row.querySelector('[name="formFieldHelp"]').value.trim(),
				required: row.querySelector('[name="formFieldRequired"]').checked,
				visibility: row.querySelector('[name="formFieldVisibility"]').value,
				order: Number(row.querySelector('[name="formFieldOrder"]').value || index),
				validation: validation,
			};
		});
	}

	function openConfigurationEditor(type, record, opener) {
		const definition = configurationDefinitions()[type];
		if (!definition) {
			return;
		}
		nodes.configForm.reset();
		nodes.configForm.elements.configType.value = type;
		nodes.configForm.elements.configId.value = record ? record.id : '';
		nodes.configTitle.textContent = record
			? UI.translate('Edit {type}', {type: definition.singular})
			: UI.translate('Add {type}', {type: definition.singular});
		UI.clear(nodes.configFields);
		definition.fields.forEach((field) => nodes.configFields.appendChild(createConfigurationField(field, record || null)));
		UI.showDialog(nodes.configDialog, opener);
	}

	function configurationPayload(type) {
		const definition = configurationDefinitions()[type];
		const payload = {};
		definition.fields.forEach(function (field) {
			if (field.type === 'formFields') {
				payload.formFields = extractFormFields();
				return;
			}
			if (field.type === 'resourceRequirements') {
				payload.resourceRequirements = extractResourceRequirements();
				return;
			}
			const input = nodes.configForm.elements[field.name];
			if (field.type === 'checkbox') {
				payload[field.name] = input.checked;
			} else if (field.type === 'multiselect') {
				payload[field.name] = Array.from(input.selectedOptions).map((optionNode) => optionNode.value);
			} else if (field.type === 'number') {
				if (input.value !== '') {
					payload[field.name] = Number(input.value);
				} else if (field.nullable) {
					payload[field.name] = null;
				}
			} else {
				payload[field.name] = input.value.trim();
			}
		});
		return payload;
	}

	async function saveConfiguration(event) {
		event.preventDefault();
		if (!nodes.configForm.reportValidity()) {
			return;
		}
		const type = nodes.configForm.elements.configType.value;
		const id = nodes.configForm.elements.configId.value;
		const submit = nodes.configForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			await UI.request(`${organizationApi(`/${type}`)}${id ? `/${encodeURIComponent(id)}` : ''}`, {
				method: id ? 'PUT' : 'POST', body: configurationPayload(type),
			});
			UI.closeDialog(nodes.configDialog);
			showStatus(UI.translate('Configuration saved.'), 'success');
			await reloadCatalog();
		} catch (error) {
			showStatus(UI.translate('The configuration could not be saved: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = false;
		}
	}

	function configurationDescription(type, record) {
		if (type === 'services') {
			const duration = record.durationMinutes ? UI.translate('{minutes} minutes', {minutes: record.durationMinutes}) : '';
			const price = record.priceMin !== null && record.priceMin !== undefined ? UI.formatMoney(record.priceMin, record.currency) : '';
			return [duration, price].filter(Boolean).join(' · ') || record.description || '';
		}
		if (type === 'staff') {
			return record.description || record.qualifications || record.timezone || '';
		}
		if (type === 'locations') {
			return [record.address, record.room].filter(Boolean).join(' · ') || record.kind || '';
		}
		return [record.type, record.capacity ? UI.translate('Capacity: {capacity}', {capacity: record.capacity}) : ''].filter(Boolean).join(' · ');
	}

	function renderConfigurationLists() {
		['services', 'staff', 'locations', 'resources'].forEach(function (type) {
			const container = document.getElementById(`appointments-${type}-list`);
			UI.clear(container);
			const items = UI.list(state.catalog[type]);
			if (!items.length) {
				container.appendChild(UI.element('div', {className: 'appointments-empty-state'}, [
					UI.element('h3', {text: UI.translate('Nothing configured yet')}),
					UI.element('p', {text: UI.translate('Add the first item to make it available for booking.')}),
				]));
				return;
			}
			items.forEach(function (record) {
				const card = UI.element('article', {className: 'appointments-config-card'});
				const heading = UI.element('div', {className: 'appointments-config-card-heading'}, [
					UI.element('h3', {text: entityName(record)}),
					UI.element('span', {className: `appointments-state ${record.active === false ? 'state-disabled' : 'state-enabled'}`, text: record.active === false ? UI.translate('Inactive') : UI.translate('Active')}),
				]);
				card.appendChild(heading);
				card.appendChild(UI.element('p', {className: 'appointments-muted', text: configurationDescription(type, record)}));
				card.appendChild(UI.element('button', {type: 'button', text: UI.translate('Edit'), onclick: (event) => openConfigurationEditor(type, record, event.currentTarget)}));
				container.appendChild(card);
			});
		});
	}

	function renderOperations() {
		const container = document.getElementById('appointments-operations-list');
		UI.clear(container);
		const failures = state.catalog.failures.length
			? state.catalog.failures
			: state.catalog.operations.filter((operation) => ['failed', 'dead', 'error'].includes(operation.status));
		if (!failures.length) {
			container.appendChild(UI.element('div', {className: 'appointments-empty-state'}, [
				UI.element('h3', {text: UI.translate('No delivery or synchronization failures')}),
				UI.element('p', {text: UI.translate('Failed mail, reminder, and calendar operations will appear here without customer details.')}),
			]));
			return;
		}
		const list = UI.element('ul', {className: 'appointments-operation-items'});
		failures.forEach(function (failure) {
			const kind = ({
				mail: UI.translate('Mail'),
				notification: UI.translate('Notification'),
				reminder: UI.translate('Reminder'),
				calendar: UI.translate('Calendar sync'),
			})[failure.type || failure.kind]
				|| UI.translate('Background operation');
			const attempts = Number(failure.attempts || failure.attemptCount || 0);
			const summary = failure.errorCode || failure.code || failure.safeMessage || UI.translate('Operation failed');
			const metadata = [];
			if (failure.createdAt) {
				metadata.push(UI.formatDateTime(failure.createdAt, organizationTimezone()));
			}
			metadata.push(attempts ? UI.translate('{count} attempts', {count: attempts}) : UI.translate('Retry pending'));
			list.appendChild(UI.element('li', {}, [
				UI.element('strong', {text: kind}),
				UI.element('span', {text: summary}),
				UI.element('small', {text: metadata.join(' · ')}),
			]));
		});
		container.appendChild(list);
	}

	async function reloadCatalog() {
		const payload = await UI.request(organizationApi('/catalog'));
		state.catalog = normalizeCatalog(payload);
		populateEntitySelectors();
		renderConfigurationLists();
		renderOperations();
		populateAvailabilitySubjects();
		populateSettings();
	}

	function availabilityCollection(type) {
		if (type === 'organization') {
			return state.organization ? [state.organization] : [];
		}
		if (type === 'service') {
			return state.catalog.services;
		}
		if (type === 'staff' && hasPermission('appointments.manage_own_availability') && !hasPermission('appointments.manage_availability')) {
			const currentUser = window.OC && typeof OC.getCurrentUser === 'function' ? OC.getCurrentUser() : (window.OC && OC.currentUser);
			const currentUid = typeof currentUser === 'string' ? currentUser : (currentUser && currentUser.uid);
			const currentStaffPublicId = state.organization.currentStaffPublicId;
			return state.catalog.staff.filter((staff) => (currentStaffPublicId && String(staff.id) === String(currentStaffPublicId)) || (currentUid && staff.userUid === currentUid));
		}
		return type === 'staff' ? state.catalog.staff : (type === 'location' ? state.catalog.locations : state.catalog.resources);
	}

	function availabilitySubjectTimezone(type, subjectId) {
		if (type === 'resource') {
			return organizationTimezone();
		}
		const subject = availabilityCollection(type).find((item) => String(item.id) === String(subjectId));
		return (subject && subject.timezone) || organizationTimezone();
	}

	function populateAvailabilitySubjects() {
		const previous = nodes.availabilitySubject.value;
		const subjects = availabilityCollection(nodes.availabilityType.value);
		resetSelect(nodes.availabilitySubject, UI.translate('Select a subject'), subjects, previous);
		if (!nodes.availabilitySubject.value && subjects.length === 1) {
			nodes.availabilitySubject.value = String(subjects[0].id);
		}
		nodes.availabilityTimezone.value = availabilitySubjectTimezone(nodes.availabilityType.value, nodes.availabilitySubject.value);
		loadAvailabilityIntoForm();
	}

	async function loadAvailabilityIntoForm() {
		const loadId = ++state.availabilityLoadId;
		const type = nodes.availabilityType.value;
		const subjectId = nodes.availabilitySubject.value;
		let rule = state.catalog.availabilityRules.find((item) => item.subjectType === type && String(item.subjectId) === String(subjectId));
		if (subjectId) {
			try {
				const payload = await UI.request(`${organizationApi('/availability')}/${encodeURIComponent(type)}/${encodeURIComponent(subjectId)}`);
				rule = payload && (payload.availability || payload);
			} catch (error) {
				if (error.status !== 404 && error.status !== 405) {
					showStatus(UI.translate('Availability could not be loaded: {message}', {message: error.message}), 'error');
				}
			}
		}
		if (loadId !== state.availabilityLoadId || type !== nodes.availabilityType.value || String(subjectId) !== String(nodes.availabilitySubject.value)) {
			return;
		}
		const weekly = UI.list(rule && (rule.weekly || rule.rules)).filter((item) => (item.type || 'available') === 'available');
		nodes.availabilityTimezone.value = (rule && rule.timezone) || availabilitySubjectTimezone(type, subjectId);
		nodes.availabilityForm.querySelectorAll('[data-weekday]').forEach(function (fieldset) {
			const weekday = Number(fieldset.dataset.weekday);
			const item = weekly.find((candidate) => Number(candidate.weekday) === weekday);
			fieldset.dataset.validFrom = item && item.validFrom ? item.validFrom : '';
			fieldset.dataset.validUntil = item && item.validUntil ? item.validUntil : '';
			fieldset.querySelector('[type="checkbox"]').checked = item ? item.enabled !== false : weekday <= 5;
			fieldset.querySelector('[name$="-start"]').value = item ? (item.start || minuteToTime(item.startMinute, '09:00')) : '09:00';
			fieldset.querySelector('[name$="-end"]').value = item ? (item.end || minuteToTime(item.endMinute, '17:00')) : '17:00';
		});
		UI.clear(nodes.breakRows);
		const breaks = UI.list(rule && (rule.breaks || rule.blockedWeekly)).concat(UI.list(rule && rule.rules).filter((item) => item.type === 'break' || item.type === 'blocked'));
		breaks.forEach((item) => nodes.breakRows.appendChild(breakRuleRow(item)));
		UI.clear(nodes.exceptionRows);
		UI.list(rule && rule.exceptions).forEach((item) => nodes.exceptionRows.appendChild(exceptionRuleRow(item)));
	}

	function weekdayOptions(selected) {
		return [
			[1, UI.translate('Monday')], [2, UI.translate('Tuesday')], [3, UI.translate('Wednesday')],
			[4, UI.translate('Thursday')], [5, UI.translate('Friday')], [6, UI.translate('Saturday')], [7, UI.translate('Sunday')],
		].map((item) => UI.option(item[0], item[1], Number(selected) === item[0]));
	}

	function breakRuleRow(rule) {
		const row = UI.element('div', {className: 'appointments-rule-row', dataset: {breakRow: 'true'}});
		row.dataset.validFrom = rule.validFrom || '';
		row.dataset.validUntil = rule.validUntil || '';
		row.appendChild(UI.element('label', {}, [UI.translate('Weekday'), UI.element('select', {name: 'breakWeekday'}, weekdayOptions(rule.weekday || 1))]));
		row.appendChild(UI.element('label', {}, [UI.translate('Start'), UI.element('input', {name: 'breakStart', type: 'time', value: rule.start || minuteToTime(rule.startMinute, '12:00'), required: true})]));
		row.appendChild(UI.element('label', {}, [UI.translate('End'), UI.element('input', {name: 'breakEnd', type: 'time', value: rule.end || minuteToTime(rule.endMinute, '13:00'), required: true})]));
		row.appendChild(UI.element('button', {type: 'button', className: 'appointments-danger-subtle', text: UI.translate('Remove'), onclick: () => row.remove()}));
		return row;
	}

	function exceptionRuleRow(rule) {
		const row = UI.element('div', {className: 'appointments-rule-row appointments-exception-row', dataset: {exceptionRow: 'true'}});
		const type = UI.element('select', {name: 'exceptionType'}, [
			UI.option('available', UI.translate('Special opening time'), rule.type === 'available'),
			UI.option('blocked', UI.translate('Blocked'), !rule.type || rule.type === 'blocked'),
			UI.option('vacation', UI.translate('Vacation'), rule.type === 'vacation'),
			UI.option('holiday', UI.translate('Holiday'), rule.type === 'holiday'),
		]);
		row.appendChild(UI.element('label', {}, [UI.translate('Type'), type]));
		row.appendChild(UI.element('label', {}, [UI.translate('Start'), UI.element('input', {name: 'exceptionStart', type: 'datetime-local', value: rule.startLocal || dateTimeInputValue(rule.startsAt || rule.start || '', nodes.availabilityTimezone.value), required: true})]));
		row.appendChild(UI.element('label', {}, [UI.translate('End'), UI.element('input', {name: 'exceptionEnd', type: 'datetime-local', value: rule.endLocal || dateTimeInputValue(rule.endsAt || rule.end || '', nodes.availabilityTimezone.value), required: true})]));
		row.appendChild(UI.element('label', {}, [UI.translate('Reason'), UI.element('input', {name: 'exceptionReason', type: 'text', value: rule.reason || '', maxlength: 255})]));
		row.appendChild(UI.element('button', {type: 'button', className: 'appointments-danger-subtle', text: UI.translate('Remove'), onclick: () => row.remove()}));
		return row;
	}

	function extractBreakRules() {
		return Array.from(nodes.breakRows.querySelectorAll('[data-break-row]')).map(function (row) {
			return {
				weekday: Number(row.querySelector('[name="breakWeekday"]').value),
				startMinute: timeToMinute(row.querySelector('[name="breakStart"]').value),
				endMinute: timeToMinute(row.querySelector('[name="breakEnd"]').value),
				type: 'blocked',
				validFrom: row.dataset.validFrom || '',
				validUntil: row.dataset.validUntil || '',
			};
		});
	}

	function extractExceptions() {
		return Array.from(nodes.exceptionRows.querySelectorAll('[data-exception-row]')).map(function (row) {
			return {
				type: row.querySelector('[name="exceptionType"]').value,
				startsAt: localDateTimeToIso(row.querySelector('[name="exceptionStart"]').value, nodes.availabilityTimezone.value.trim()),
				endsAt: localDateTimeToIso(row.querySelector('[name="exceptionEnd"]').value, nodes.availabilityTimezone.value.trim()),
				reason: row.querySelector('[name="exceptionReason"]').value.trim(),
			};
		});
	}

	async function saveAvailability(event) {
		event.preventDefault();
		if (!nodes.availabilityForm.reportValidity()) {
			return;
		}
		const type = nodes.availabilityType.value;
		const subjectId = nodes.availabilitySubject.value;
		if (!subjectId) {
			showStatus(UI.translate('Select a subject first.'), 'error');
			return;
		}
		const weekly = Array.from(nodes.availabilityForm.querySelectorAll('[data-weekday]')).filter(function (fieldset) {
			return fieldset.querySelector('[type="checkbox"]').checked;
		}).map(function (fieldset) {
			return {
				weekday: Number(fieldset.dataset.weekday),
				startMinute: timeToMinute(fieldset.querySelector('[name$="-start"]').value),
				endMinute: timeToMinute(fieldset.querySelector('[name$="-end"]').value),
				type: 'available',
				validFrom: fieldset.dataset.validFrom || '',
				validUntil: fieldset.dataset.validUntil || '',
			};
		});
		const submit = nodes.availabilityForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			await UI.request(`${organizationApi('/availability')}/${encodeURIComponent(type)}/${encodeURIComponent(subjectId)}`, {
				method: 'PUT', body: {rules: weekly.concat(extractBreakRules()), exceptions: extractExceptions()},
			});
			showStatus(UI.translate('Availability saved.'), 'success');
			await reloadCatalog();
		} catch (error) {
			showStatus(UI.translate('Availability could not be saved: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = false;
		}
	}

	function populateSettings() {
		const settings = state.catalog.settings || {};
		const values = Object.assign({
				name: entityName(state.organization),
				locale: state.organization.locale || 'de',
				timezone: state.organization.timezone || 'Europe/Berlin',
				accentColor: '#00679e',
				slotInterval: 15,
				minimumFormSeconds: 3,
				retentionDays: 365,
				publicEnabled: false,
			}, settings);
		Array.from(nodes.settingsForm.elements).forEach(function (input) {
			if (input.name && values[input.name] !== undefined && values[input.name] !== null) {
				if (input.type === 'checkbox') {
					input.checked = Boolean(values[input.name]);
				} else {
					input.value = values[input.name];
				}
			}
		});
		syncPublicSettingsRequirements();
		const slug = state.organization.slug;
		if (slug) {
			const path = `/apps/appointments/book/${encodeURIComponent(slug)}`;
			nodes.bookingPageLink.href = window.OC && typeof OC.generateUrl === 'function' ? OC.generateUrl(path) : path;
			nodes.bookingPageLink.hidden = false;
		} else {
			nodes.bookingPageLink.hidden = true;
		}
	}

	function syncPublicSettingsRequirements() {
		nodes.settingsForm.elements.privacyUrl.required = nodes.settingsForm.elements.publicEnabled.checked;
	}

	async function saveSettings(event) {
		event.preventDefault();
		if (!nodes.settingsForm.reportValidity()) {
			return;
		}
		const values = new FormData(nodes.settingsForm);
		const payload = {};
		values.forEach((value, key) => { payload[key] = String(value).trim(); });
		payload.publicEnabled = nodes.settingsForm.elements.publicEnabled.checked;
		['slotInterval', 'minimumFormSeconds', 'retentionDays'].forEach((key) => { payload[key] = Number(payload[key]); });
		const submit = nodes.settingsForm.querySelector('button[type="submit"]');
		submit.disabled = true;
		try {
			await UI.request(organizationApi('/settings'), {method: 'PUT', body: payload});
			showStatus(UI.translate('Booking page settings saved.'), 'success');
			await reloadCatalog();
		} catch (error) {
			showStatus(UI.translate('Settings could not be saved: {message}', {message: error.message}), 'error');
		} finally {
			submit.disabled = false;
		}
	}

	function switchSection(section) {
		state.section = section;
		root.querySelectorAll('[data-section-target]').forEach(function (button) {
			const current = button.dataset.sectionTarget === section;
			button.setAttribute('aria-current', current ? 'page' : 'false');
		});
		root.querySelectorAll('[data-section-panel]').forEach(function (panel) {
			panel.hidden = panel.dataset.sectionPanel !== section;
		});
		const labels = {
			calendar: [UI.translate('Appointments'), UI.translate('Manage bookings and availability.')],
			services: [UI.translate('Services'), UI.translate('Define durations, prices, rules, and booking instructions.')],
			staff: [UI.translate('Staff'), UI.translate('Connect Office users to bookable staff profiles.')],
			locations: [UI.translate('Locations'), UI.translate('Manage on-site and remote appointment types.')],
			resources: [UI.translate('Resources'), UI.translate('Prevent rooms, vehicles, and equipment from being double-booked.')],
			availability: [UI.translate('Availability'), UI.translate('Set recurring bookable hours.')],
			'booking-page': [UI.translate('Booking page'), UI.translate('Configure the public booking experience.')],
			operations: [UI.translate('Notifications and integrations'), UI.translate('Review non-sensitive delivery and synchronization failures.')],
		};
		nodes.pageTitle.textContent = labels[section][0];
		nodes.pageSubtitle.textContent = labels[section][1];
		nodes.newAppointment.hidden = section !== 'calendar' || !canManageAppointments();
	}

	function clearFilters() {
		nodes.search.value = '';
		[nodes.filterStaff, nodes.filterLocation, nodes.filterService, nodes.filterStatus, nodes.filterResource].forEach((select) => { select.value = ''; });
		loadAppointments();
	}

	function bindEvents() {
		UI.bindDialogDismiss(root);
		nodes.onboardingForm.addEventListener('submit', createOrganization);
		let slugEdited = false;
		nodes.onboardingSlug.addEventListener('input', () => { slugEdited = true; });
		nodes.onboardingName.addEventListener('input', function () {
			if (!slugEdited) {
				nodes.onboardingSlug.value = slugify(nodes.onboardingName.value);
			}
		});
		nodes.organization.addEventListener('change', () => selectOrganization(nodes.organization.value));
		nodes.newAppointment.addEventListener('click', (event) => openAppointmentEditor(null, event.currentTarget));
		nodes.appointmentForm.addEventListener('submit', saveAppointment);
		nodes.appointmentForm.elements.serviceId.addEventListener('change', renderAppointmentCustomFields);
		nodes.configForm.addEventListener('submit', saveConfiguration);
		nodes.availabilityForm.addEventListener('submit', saveAvailability);
		nodes.settingsForm.addEventListener('submit', saveSettings);
		nodes.settingsForm.elements.publicEnabled.addEventListener('change', syncPublicSettingsRequirements);
		nodes.availabilityType.addEventListener('change', populateAvailabilitySubjects);
		nodes.availabilitySubject.addEventListener('change', loadAvailabilityIntoForm);
		document.getElementById('appointments-add-break').addEventListener('click', () => nodes.breakRows.appendChild(breakRuleRow({})));
		document.getElementById('appointments-add-exception').addEventListener('click', () => nodes.exceptionRows.appendChild(exceptionRuleRow({type: 'blocked'})));
		root.querySelectorAll('[data-section-target]').forEach((button) => button.addEventListener('click', () => switchSection(button.dataset.sectionTarget)));
		root.querySelectorAll('[data-config-create]').forEach((button) => button.addEventListener('click', (event) => openConfigurationEditor(button.dataset.configCreate, null, event.currentTarget)));
		root.querySelectorAll('[data-view]').forEach(function (button) {
			button.addEventListener('click', function () {
				state.view = button.dataset.view;
				root.querySelectorAll('[data-view]').forEach((candidate) => candidate.setAttribute('aria-pressed', candidate === button ? 'true' : 'false'));
				loadAppointments();
			});
		});
		document.getElementById('appointments-period-previous').addEventListener('click', () => movePeriod(-1));
		document.getElementById('appointments-period-today').addEventListener('click', function () { state.anchor = organizationToday(); loadAppointments(); });
		document.getElementById('appointments-period-next').addEventListener('click', () => movePeriod(1));
		document.getElementById('appointments-clear-filters').addEventListener('click', clearFilters);
		[nodes.filterStaff, nodes.filterLocation, nodes.filterService, nodes.filterStatus, nodes.filterResource]
			.forEach((select) => select.addEventListener('change', loadAppointments));
		nodes.search.addEventListener('input', UI.debounce(loadAppointments, 300));
	}

	bindEvents();
	loadContext();
}());
