(function () {
	'use strict';

	const root = document.getElementById('appointments-public');
	if (!root || !window.AppointmentsUI) {
		return;
	}

	const UI = window.AppointmentsUI;
	const apiBase = root.dataset.apiBase.replace(/\/$/, '');
	const organizationSlug = root.dataset.organizationSlug;
	const publicBase = `${apiBase}/${encodeURIComponent(organizationSlug)}`;
	const requestedServiceSlug = new URLSearchParams(window.location.search).get('service') || '';
	const nodes = {
		name: document.getElementById('appointments-public-name'),
		description: document.getElementById('appointments-public-description'),
		contactInfo: document.getElementById('appointments-public-contact-info'),
		logo: document.getElementById('appointments-public-logo'),
		status: document.getElementById('appointments-public-status'),
		shell: document.getElementById('appointments-booking-shell'),
		form: document.getElementById('appointments-public-form'),
		services: document.getElementById('appointments-public-services'),
		locations: document.getElementById('appointments-public-locations'),
		locationGroup: document.getElementById('appointments-public-location-group'),
		staff: document.getElementById('appointments-public-staff'),
		staffGroup: document.getElementById('appointments-public-staff-group'),
		date: document.getElementById('appointments-public-date'),
		timezone: document.getElementById('appointments-public-timezone'),
		slots: document.getElementById('appointments-public-slots'),
		slotsStatus: document.getElementById('appointments-public-slots-status'),
		customFields: document.getElementById('appointments-public-custom-fields'),
		review: document.getElementById('appointments-public-review'),
		privacy: document.getElementById('appointments-public-privacy'),
		legal: document.getElementById('appointments-public-legal'),
		policy: document.getElementById('appointments-public-policy'),
		back: document.getElementById('appointments-public-back'),
		next: document.getElementById('appointments-public-next'),
		submit: document.getElementById('appointments-public-submit'),
		confirmation: document.getElementById('appointments-public-confirmation'),
		confirmationMessage: document.getElementById('appointments-confirmation-message'),
		confirmationDetails: document.getElementById('appointments-confirmation-details'),
		confirmationManage: document.getElementById('appointments-confirmation-manage'),
		confirmationIcs: document.getElementById('appointments-confirmation-ics'),
	};

	const state = {
		catalog: null,
		organization: null,
		settings: {},
		services: [],
		locations: [],
		staff: [],
		step: 1,
		serviceId: '',
		locationId: '',
		staffId: '',
		slot: null,
		slotsRequest: 0,
		managementToken: '',
	};

	function showStatus(message, kind) {
		nodes.status.textContent = message || '';
		nodes.status.className = `appointments-status${kind ? ` is-${kind}` : ''}`;
	}

	function itemName(item) {
		return item ? (item.displayName || item.name || item.title || UI.translate('Unnamed')) : '';
	}

	function currentService() {
		return state.services.find((item) => String(item.id) === String(state.serviceId));
	}

	function activeServiceSlug() {
		const service = currentService();
		return requestedServiceSlug && service && service.slug === requestedServiceSlug ? requestedServiceSlug : '';
	}

	function currentLocation() {
		return state.locations.find((item) => String(item.id) === String(state.locationId));
	}

	function currentStaff() {
		return state.staff.find((item) => String(item.id) === String(state.staffId));
	}

	function updateDateLimits() {
		const today = UI.dateKeyInTimeZone(new Date(), timezone());
		nodes.date.min = today;
		const horizon = Number((currentService() || {}).maximumHorizonDays);
		if (Number.isFinite(horizon) && horizon > 0) {
			const parts = today.split('-').map(Number);
			const maximum = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + horizon));
			nodes.date.max = `${maximum.getUTCFullYear()}-${String(maximum.getUTCMonth() + 1).padStart(2, '0')}-${String(maximum.getUTCDate()).padStart(2, '0')}`;
		} else {
			nodes.date.removeAttribute('max');
		}
		if (!nodes.date.value || nodes.date.value < nodes.date.min || (nodes.date.max && nodes.date.value > nodes.date.max)) {
			nodes.date.value = today;
		}
	}

	function setAccentColor(color) {
		if (/^#[0-9a-f]{6}$/i.test(color || '')) {
			root.style.setProperty('--appointments-accent', color);
			const channels = [1, 3, 5].map(function (offset) {
				const component = Number.parseInt(color.slice(offset, offset + 2), 16) / 255;
				return component <= 0.04045 ? component / 12.92 : Math.pow((component + 0.055) / 1.055, 2.4);
			});
			const luminance = (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2]);
			const contrastWithBlack = (luminance + 0.05) / 0.05;
			const contrastWithWhite = 1.05 / (luminance + 0.05);
			root.style.setProperty('--appointments-accent-text', contrastWithBlack >= contrastWithWhite ? '#000000' : '#ffffff');
		}
	}

	function setSafeLink(node, value) {
		const url = UI.safeUrl(value, true);
		if (url) {
			node.href = url;
			node.hidden = false;
		} else {
			node.hidden = true;
		}
	}

	function managementPageUrl() {
		if (window.OC && typeof OC.generateUrl === 'function') {
			return OC.generateUrl('/apps/appointments/manage');
		}
		return `${apiBase.replace(/\/public\/v1$/, '')}/manage`;
	}

	async function loadCatalog() {
		showStatus(UI.translate('Loading booking page…'));
		try {
			const catalogParameters = new URLSearchParams();
			if (requestedServiceSlug) {
				catalogParameters.set('service', requestedServiceSlug);
			}
			const payload = await UI.request(`${publicBase}/catalog${catalogParameters.toString() ? `?${catalogParameters.toString()}` : ''}`);
			const catalog = payload && payload.catalog ? payload.catalog : (payload || {});
			state.catalog = catalog;
			state.organization = catalog.organization || payload.organization || {};
			state.settings = catalog.settings || state.organization || {};
			state.services = UI.list(catalog.services).filter(function (item) {
				return item.active !== false && (item.visibility === 'public' || (requestedServiceSlug && item.slug === requestedServiceSlug));
			});
			state.locations = UI.list(catalog.locations).filter((item) => item.active !== false);
			state.staff = UI.list(catalog.staff).filter((item) => item.active !== false && item.publicBooking !== false);
			applyOrganizationBranding();
			renderServices();
			nodes.form.elements.bookingStartedAt.value = String(Math.floor(Date.now() / 1000));
			updateDateLimits();
			nodes.shell.hidden = false;
			showStatus('');
			if (!state.services.length) {
				showStatus(UI.translate('No services are currently available for online booking.'), 'info');
				nodes.next.disabled = true;
			}
		} catch (error) {
			showStatus(UI.translate('The booking page could not be loaded: {message}', {message: error.message}), 'error');
		}
	}

	function applyOrganizationBranding() {
		nodes.name.textContent = state.settings.name || itemName(state.organization) || UI.translate('Book an appointment');
		nodes.description.textContent = state.settings.description || state.organization.description || '';
		const contactInfo = state.settings.contactInfo || state.organization.contactInfo || '';
		nodes.contactInfo.textContent = contactInfo;
		nodes.contactInfo.hidden = !contactInfo;
		setAccentColor(state.settings.accentColor);
		const logo = UI.safeUrl(state.settings.logoUrl, true);
		if (logo && new URL(logo, window.location.origin).origin === window.location.origin) {
			nodes.logo.src = logo;
			nodes.logo.hidden = false;
		}
		const timezone = state.settings.timezone || state.organization.timezone || 'Europe/Berlin';
		nodes.timezone.textContent = UI.translate('All times are shown in {timezone}.', {timezone: timezone});
		setSafeLink(nodes.privacy, state.settings.privacyUrl);
		setSafeLink(nodes.legal, state.settings.imprintUrl);
		if (state.settings.cancellationPolicy) {
			nodes.policy.textContent = state.settings.cancellationPolicy;
			nodes.policy.hidden = false;
		}
	}

	function choiceCard(groupName, item, description, checked, testId) {
		const input = UI.element('input', {
			type: 'radio', name: groupName, value: item.id, checked: checked, required: true,
			dataset: testId ? {testid: testId} : {},
		});
		const label = UI.element('label', {className: 'appointments-choice-card'}, [
			input,
			UI.element('span', {className: 'appointments-choice-title', text: itemName(item)}),
		]);
		if (description) {
			label.appendChild(UI.element('span', {className: 'appointments-choice-description', text: description}));
		}
		return {label: label, input: input};
	}

	function serviceDescription(service) {
		const parts = [];
		if (service.durationMinutes) {
			parts.push(UI.translate('{minutes} minutes', {minutes: service.durationMinutes}));
		}
		if (service.priceMin !== undefined && service.priceMin !== null) {
			const price = UI.formatMoney(service.priceMin, service.currency);
			parts.push(service.priceMax && Number(service.priceMax) !== Number(service.priceMin)
				? UI.translate('{minimum} – {maximum}', {minimum: price, maximum: UI.formatMoney(service.priceMax, service.currency)})
				: price);
		}
		if (service.description) {
			parts.push(service.description);
		}
		return parts.join(' · ');
	}

	function renderServices() {
		UI.clear(nodes.services);
		const requestedIndex = requestedServiceSlug ? state.services.findIndex((service) => service.slug === requestedServiceSlug) : -1;
		const selectedIndex = requestedIndex >= 0 ? requestedIndex : 0;
		state.services.forEach(function (service, index) {
			const choice = choiceCard('serviceId', service, serviceDescription(service), index === selectedIndex, 'public-service');
			choice.input.addEventListener('change', function () {
				state.serviceId = String(service.id);
				state.slot = null;
				renderDependentChoices();
				renderCustomFields();
			});
			nodes.services.appendChild(choice.label);
		});
		if (state.services.length) {
			state.serviceId = String(state.services[selectedIndex].id);
			renderDependentChoices();
			renderCustomFields();
		}
	}

	function allowedForService(items, allowedIds) {
		if (!Array.isArray(allowedIds) || !allowedIds.length) {
			return items;
		}
		const allowed = new Set(allowedIds.map(String));
		return items.filter((item) => allowed.has(String(item.id)));
	}

	function renderDependentChoices() {
		const service = currentService() || {};
		const locations = Array.isArray(service.locationIds) && service.locationIds.length
			? allowedForService(state.locations, service.locationIds)
			: state.locations.filter((location) => location.kind === service.appointmentType);
		nodes.form.elements.phone.required = Boolean(service.phoneRequired);
		updateDateLimits();
		UI.clear(nodes.locations);
		nodes.locationGroup.hidden = !locations.length;
		state.locationId = locations.length ? String(locations[0].id) : '';
		locations.forEach(function (location, index) {
			const description = [location.address, location.room, location.publicNotes, location.directions, location.accessibility].filter(Boolean).join(' · ');
			const choice = choiceCard('locationId', location, description, index === 0);
			choice.input.addEventListener('change', () => {
				state.locationId = String(location.id);
				state.slot = null;
				renderStaffChoices(service);
			});
			nodes.locations.appendChild(choice.label);
		});
		renderStaffChoices(service);
	}

	function renderStaffChoices(service) {
		const serviceStaff = allowedForService(state.staff, service.staffIds);
		const staff = serviceStaff.filter(function (member) {
			return !state.locationId || !Array.isArray(member.locationIds) || !member.locationIds.length
				|| member.locationIds.map(String).includes(String(state.locationId));
		});
		UI.clear(nodes.staff);
		const anyStaff = {id: '__any__', name: UI.translate('Any available staff member')};
		const anyChoice = choiceCard('staffId', anyStaff, UI.translate('We will choose a qualified available person.'), true);
		anyChoice.input.addEventListener('change', () => { state.staffId = ''; state.slot = null; });
		nodes.staff.appendChild(anyChoice.label);
		state.staffId = '';
		staff.forEach(function (member) {
			const choice = choiceCard('staffId', member, member.description || member.qualifications || '', false);
			choice.input.addEventListener('change', () => { state.staffId = String(member.id); state.slot = null; });
			nodes.staff.appendChild(choice.label);
		});
		nodes.staffGroup.hidden = !staff.length;
	}

	function customFieldControl(field) {
		const type = field.type || 'text';
		const validation = field.validation || {};
		let input;
		if (type === 'textarea') {
			input = UI.element('textarea', {
				name: `custom-${field.id}`, rows: 4, required: field.required,
				minLength: validation.min, maxLength: validation.max || 5000,
			});
		} else if (type === 'select' || type === 'multi_select') {
			input = UI.element('select', {name: `custom-${field.id}`, required: field.required, multiple: type === 'multi_select'});
			if (type === 'select' && !field.required) {
				input.appendChild(UI.option('', UI.translate('Select an option')));
			}
			UI.list(validation.options).forEach((value) => input.appendChild(UI.option(value.value !== undefined ? value.value : value, value.label || value)));
		} else if (type === 'checkbox') {
			input = UI.element('input', {name: `custom-${field.id}`, type: 'checkbox', required: field.required});
		} else if (type === 'boolean') {
			input = UI.element('select', {name: `custom-${field.id}`, required: field.required}, [
				UI.option('', UI.translate('Select an option')),
				UI.option('true', UI.translate('Yes')),
				UI.option('false', UI.translate('No')),
			]);
		} else {
			const inputType = ({phone: 'tel', email: 'email', number: 'number', date: 'date'})[type] || 'text';
			input = UI.element('input', {
				name: `custom-${field.id}`, type: inputType, required: field.required,
				min: type === 'number' ? validation.min : null,
				max: type === 'number' ? validation.max : null,
				minLength: type === 'text' || type === 'phone' || type === 'email' ? validation.min : null,
				maxLength: type === 'text' || type === 'phone' || type === 'email' ? (validation.max || 512) : null,
			});
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

	function renderCustomFields() {
		UI.clear(nodes.customFields);
		UI.list((currentService() || {}).formFields).filter((field) => field.visibility !== 'internal')
			.sort((a, b) => Number(a.order || 0) - Number(b.order || 0))
			.forEach((field) => nodes.customFields.appendChild(customFieldControl(field)));
	}

	function timezone() {
		return state.settings.timezone || state.organization.timezone || 'Europe/Berlin';
	}

	async function loadSlots() {
		const requestId = ++state.slotsRequest;
		if (!state.serviceId || !nodes.date.value) {
			UI.clear(nodes.slots);
			return;
		}
		state.slot = null;
		UI.clear(nodes.slots);
		nodes.slotsStatus.textContent = UI.translate('Loading available times…');
		const parameters = new URLSearchParams({serviceId: state.serviceId, date: nodes.date.value, timezone: timezone()});
		if (activeServiceSlug()) {
			parameters.set('service', activeServiceSlug());
		}
		if (state.locationId) {
			parameters.set('locationId', state.locationId);
		}
		if (state.staffId) {
			parameters.set('staffId', state.staffId);
		}
		try {
			const payload = await UI.request(`${publicBase}/slots?${parameters.toString()}`);
			if (requestId !== state.slotsRequest) {
				return;
			}
			const slots = UI.list(payload && (payload.slots || payload.items || payload));
			nodes.slotsStatus.textContent = slots.length ? '' : UI.translate('No available times were found for this date.');
			slots.forEach(function (slotValue) {
				const slot = typeof slotValue === 'string' ? {startsAt: slotValue} : slotValue;
				const startsAt = slot.startsAt || slot.startAt || slot.start;
				const input = UI.element('input', {type: 'radio', name: 'slot', value: startsAt, required: true, dataset: {testid: 'public-slot'}});
				const label = UI.element('label', {className: 'appointments-slot'}, [input, UI.element('span', {text: UI.formatTimeWithZone(startsAt, timezone())})]);
				if (slot.staffName) {
					label.appendChild(UI.element('small', {text: slot.staffName}));
				}
				input.addEventListener('change', function () { state.slot = slot; });
				nodes.slots.appendChild(label);
				});
		} catch (error) {
			if (requestId !== state.slotsRequest) {
				return;
			}
			nodes.slotsStatus.textContent = UI.translate('Available times could not be loaded: {message}', {message: error.message});
		}
	}

	function controlsForStep(step) {
		const panel = root.querySelector(`[data-booking-step="${step}"]`);
		return Array.from(panel.querySelectorAll('input, select, textarea')).filter((control) => !control.disabled && control.type !== 'hidden');
	}

	function validateStep(step) {
		if (step === 1 && !state.serviceId) {
			showStatus(UI.translate('Choose a service to continue.'), 'error');
			return false;
		}
		if (step === 2 && !state.slot) {
			showStatus(UI.translate('Choose an available time to continue.'), 'error');
			return false;
		}
		const invalid = controlsForStep(step).find((control) => !control.checkValidity());
		if (invalid) {
			invalid.reportValidity();
			invalid.focus();
			return false;
		}
		showStatus('');
		return true;
	}

	function setStep(step) {
		state.step = Math.max(1, Math.min(4, step));
		root.querySelectorAll('[data-booking-step]').forEach((panel) => { panel.hidden = Number(panel.dataset.bookingStep) !== state.step; });
		root.querySelectorAll('[data-progress-step]').forEach(function (item) {
			if (Number(item.dataset.progressStep) === state.step) {
				item.setAttribute('aria-current', 'step');
			} else {
				item.removeAttribute('aria-current');
			}
		});
		nodes.back.hidden = state.step === 1;
		nodes.next.hidden = state.step === 4;
		nodes.submit.hidden = state.step !== 4;
		if (state.step === 2) {
			loadSlots();
		}
		if (state.step === 4) {
			renderReview();
		}
		const heading = root.querySelector(`[data-booking-step="${state.step}"] h2`);
		if (heading) {
			heading.tabIndex = -1;
			heading.focus({preventScroll: true});
			const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
			root.querySelector(`[data-booking-step="${state.step}"]`).scrollIntoView({behavior: reduceMotion ? 'auto' : 'smooth', block: 'start'});
		}
	}

	function summaryEntry(list, term, description) {
		list.appendChild(UI.element('dt', {text: term}));
		list.appendChild(UI.element('dd', {text: description || '—'}));
	}

	function renderReview() {
		UI.clear(nodes.review);
		const form = nodes.form.elements;
		const staff = currentStaff();
		const service = currentService();
		summaryEntry(nodes.review, UI.translate('Service'), itemName(currentService()));
		summaryEntry(nodes.review, UI.translate('Date and time'), UI.formatDateTime(state.slot && (state.slot.startsAt || state.slot.startAt || state.slot.start), timezone()));
		summaryEntry(nodes.review, UI.translate('Staff'), staff ? itemName(staff) : UI.translate('Any available staff member'));
		summaryEntry(nodes.review, UI.translate('Location'), itemName(currentLocation()) || UI.translate('Remote appointment'));
		summaryEntry(nodes.review, UI.translate('Name'), `${form.firstName.value} ${form.lastName.value}`.trim());
		summaryEntry(nodes.review, UI.translate('Email'), form.email.value);
		if (service && service.bookingNotes) {
			summaryEntry(nodes.review, UI.translate('Information'), service.bookingNotes);
		}
	}

	function customAnswers() {
		return UI.list((currentService() || {}).formFields).filter((field) => field.visibility !== 'internal').reduce(function (answers, field) {
			const control = nodes.form.elements[`custom-${field.id}`];
			let value;
			if (!control) {
				value = null;
			} else if (control instanceof RadioNodeList) {
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

	async function downloadIcs(token) {
		try {
			const headers = {'Accept': 'text/calendar', 'Content-Type': 'application/json'};
			if (window.OC && OC.requestToken) {
				headers.requesttoken = OC.requestToken;
			}
			const response = await fetch(`${apiBase}/manage/ics`, {
				method: 'POST', credentials: 'same-origin', headers: headers, body: JSON.stringify({token: token}),
			});
			if (!response.ok) {
				throw new Error(UI.translate('Calendar download failed.'));
			}
			const blob = await response.blob();
			const url = URL.createObjectURL(blob);
			const link = UI.element('a', {href: url, download: 'appointment.ics'});
			document.body.appendChild(link);
			link.click();
			link.remove();
			URL.revokeObjectURL(url);
		} catch (error) {
			showStatus(error.message, 'error');
		}
	}

	async function submitBooking(event) {
		event.preventDefault();
		if (!validateStep(4) || !state.slot) {
			return;
		}
		const values = new FormData(nodes.form);
		const startsAt = state.slot.startsAt || state.slot.startAt || state.slot.start;
		const payload = {
			serviceId: state.serviceId,
			serviceSlug: activeServiceSlug() || null,
			locationId: state.locationId || null,
			staffId: state.staffId || state.slot.staffId || null,
			startsAt: startsAt,
			timezone: timezone(),
			contact: {
				firstName: String(values.get('firstName') || '').trim(),
				lastName: String(values.get('lastName') || '').trim(),
				email: String(values.get('email') || '').trim(),
				phone: String(values.get('phone') || '').trim(),
			},
			message: String(values.get('message') || '').trim(),
			privacyAccepted: values.get('privacyAccepted') === 'on',
			formAnswers: customAnswers(),
			antiSpam: {
				website: String(values.get('website') || ''),
				bookingStartedAt: Number(values.get('bookingStartedAt') || 0),
			},
		};
		nodes.submit.disabled = true;
		nodes.submit.textContent = UI.translate('Booking…');
		try {
			const response = await UI.request(`${publicBase}/book`, {method: 'POST', body: payload});
			showConfirmation(response || {}, payload);
		} catch (error) {
			showStatus(UI.translate('The appointment could not be booked: {message}', {message: error.message}), 'error');
			nodes.submit.disabled = false;
			nodes.submit.textContent = UI.translate('Book appointment');
			if (error.status === 409) {
				setStep(2);
				nodes.slotsStatus.textContent = UI.translate('This time was just booked by someone else. Please choose another time.');
				loadSlots();
			}
		}
	}

	function showConfirmation(response, requestPayload) {
		const appointment = response.appointment || response;
		state.managementToken = response.managementToken || appointment.managementToken || '';
		nodes.shell.hidden = true;
		nodes.confirmation.hidden = false;
		nodes.confirmationMessage.textContent = response.message || state.settings.confirmationText || UI.translate('Thank you. Your booking has been received.');
		UI.clear(nodes.confirmationDetails);
		summaryEntry(nodes.confirmationDetails, UI.translate('Booking number'), appointment.bookingNumber || response.bookingNumber);
		summaryEntry(nodes.confirmationDetails, UI.translate('Service'), itemName(currentService()));
		summaryEntry(nodes.confirmationDetails, UI.translate('Date and time'), UI.formatDateTime(appointment.startsAt || requestPayload.startsAt, timezone()));
		if (currentService() && currentService().preparation) {
			summaryEntry(nodes.confirmationDetails, UI.translate('Information'), currentService().preparation);
		}
		if (state.managementToken) {
			nodes.confirmationManage.href = `${managementPageUrl()}#${encodeURIComponent(state.managementToken)}`;
			nodes.confirmationManage.hidden = false;
			nodes.confirmationIcs.hidden = false;
			nodes.confirmationIcs.addEventListener('click', () => downloadIcs(state.managementToken), {once: true});
		}
		nodes.confirmation.focus();
	}

	nodes.next.addEventListener('click', function () {
		if (validateStep(state.step)) {
			setStep(state.step + 1);
		}
	});
	nodes.back.addEventListener('click', () => setStep(state.step - 1));
	nodes.date.addEventListener('change', loadSlots);
	nodes.form.addEventListener('submit', submitBooking);
	loadCatalog();
}());
