(function () {
	'use strict';

	const dialogOpeners = new WeakMap();

	function translate(source, replacements) {
		if (typeof window.t === 'function') {
			return window.t('appointments', source, replacements || {});
		}
		return Object.entries(replacements || {}).reduce(function (value, entry) {
			return value.replaceAll(`{${entry[0]}}`, String(entry[1]));
		}, source);
	}

	function appendChildren(node, children) {
		(children || []).flat().forEach(function (child) {
			if (child === null || child === undefined || child === false) {
				return;
			}
			node.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
		});
		return node;
	}

	function element(tag, attributes, children) {
		const node = document.createElement(tag);
		Object.entries(attributes || {}).forEach(function (entry) {
			const key = entry[0];
			const value = entry[1];
			if (value === null || value === undefined || value === false) {
				return;
			}
			if (key === 'className') {
				node.className = String(value);
			} else if (key === 'text') {
				node.textContent = String(value);
			} else if (key === 'dataset') {
				Object.entries(value).forEach((item) => { node.dataset[item[0]] = String(item[1]); });
			} else if (key === 'checked' || key === 'selected' || key === 'disabled' || key === 'hidden' || key === 'required') {
				node[key] = Boolean(value);
			} else if (key.startsWith('on') && typeof value === 'function') {
				node.addEventListener(key.slice(2).toLowerCase(), value);
			} else if (key in node && !key.startsWith('aria')) {
				try {
					node[key] = value;
				} catch (_error) {
					node.setAttribute(key, String(value));
				}
			} else {
				node.setAttribute(key, String(value));
			}
		});
		return appendChildren(node, children);
	}

	function clear(node) {
		node.replaceChildren();
		return node;
	}

	function option(value, label, selected) {
		return element('option', {value: value, text: label, selected: Boolean(selected)});
	}

	async function request(url, options) {
		const settings = Object.assign({method: 'GET', credentials: 'same-origin'}, options || {});
		const headers = new Headers(settings.headers || {});
		headers.set('Accept', 'application/json');
		if (settings.body && typeof settings.body !== 'string' && !(settings.body instanceof FormData)) {
			headers.set('Content-Type', 'application/json');
			settings.body = JSON.stringify(settings.body);
		}
		if (window.OC && OC.requestToken && !headers.has('requesttoken')) {
			headers.set('requesttoken', OC.requestToken);
		}
		settings.headers = headers;
		const response = await fetch(url, settings);
		const contentType = response.headers.get('content-type') || '';
		let payload = null;
		if (response.status !== 204) {
			payload = contentType.includes('json') ? await response.json() : await response.text();
		}
		if (!response.ok) {
			const message = payload && typeof payload === 'object'
				? (payload.error && (payload.error.message || payload.error)) || payload.message
				: payload;
			const error = new Error(typeof message === 'string' && message ? message : translate('Request failed.'));
			error.status = response.status;
			error.payload = payload;
			throw error;
		}
		return payload;
	}

	function locale() {
		return document.documentElement.lang || navigator.language || 'en';
	}

	function asDate(value) {
		let normalized = value;
		if (typeof normalized === 'number' && Number.isFinite(normalized) && Math.abs(normalized) < 100000000000) {
			normalized *= 1000;
		} else if (typeof normalized === 'string' && /^-?\d{1,11}$/.test(normalized.trim())) {
			normalized = Number(normalized) * 1000;
		}
		const date = normalized instanceof Date ? normalized : new Date(normalized);
		return Number.isNaN(date.getTime()) ? null : date;
	}

	function formatDate(value, timeZone, options) {
		const date = asDate(value);
		if (!date) {
			return translate('Unknown date');
		}
		return new Intl.DateTimeFormat(locale(), Object.assign({dateStyle: 'medium', timeZone: timeZone || undefined}, options || {})).format(date);
	}

	function formatTime(value, timeZone) {
		const date = asDate(value);
		if (!date) {
			return translate('Unknown time');
		}
		return new Intl.DateTimeFormat(locale(), {hour: '2-digit', minute: '2-digit', timeZone: timeZone || undefined}).format(date);
	}

	function formatTimeWithZone(value, timeZone) {
		const date = asDate(value);
		if (!date) {
			return translate('Unknown time');
		}
		try {
			return new Intl.DateTimeFormat(locale(), {hour: '2-digit', minute: '2-digit', timeZone: timeZone || undefined, timeZoneName: 'shortOffset'}).format(date);
		} catch (_error) {
			return new Intl.DateTimeFormat(locale(), {hour: '2-digit', minute: '2-digit', timeZone: timeZone || undefined, timeZoneName: 'short'}).format(date);
		}
	}

	function formatDateTime(value, timeZone) {
		const date = asDate(value);
		if (!date) {
			return translate('Unknown date');
		}
		return new Intl.DateTimeFormat(locale(), {dateStyle: 'full', timeStyle: 'short', timeZone: timeZone || undefined}).format(date);
	}

	function formatMoney(value, currency) {
		const number = Number(value);
		if (!Number.isFinite(number)) {
			return '';
		}
		try {
			return new Intl.NumberFormat(locale(), {style: 'currency', currency: currency || 'EUR'}).format(number);
		} catch (_error) {
			return `${number.toFixed(2)} ${currency || 'EUR'}`;
		}
	}

	function statusLabel(status) {
		return ({
			pending: translate('Pending'),
			confirmed: translate('Confirmed'),
			cancelled_by_customer: translate('Cancelled by customer'),
			cancelled_by_staff: translate('Cancelled by staff'),
			completed: translate('Completed'),
			no_show: translate('No-show'),
			rescheduled: translate('Rescheduled'),
		})[status] || status || translate('Unknown status');
	}

	function safeUrl(value, allowRelative) {
		if (!value) {
			return null;
		}
		try {
			const parsed = new URL(value, window.location.origin);
			if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
				return null;
			}
			if (!allowRelative && !/^https?:\/\//i.test(value)) {
				return null;
			}
			return allowRelative && parsed.origin === window.location.origin ? `${parsed.pathname}${parsed.search}${parsed.hash}` : parsed.href;
		} catch (_error) {
			return null;
		}
	}

	function showDialog(dialog, opener) {
		if (!dialog) {
			return;
		}
		dialogOpeners.set(dialog, opener || document.activeElement);
		if (typeof dialog.showModal === 'function') {
			dialog.showModal();
		} else {
			dialog.setAttribute('open', '');
		}
		const target = dialog.querySelector('input:not([type="hidden"]), select, textarea, button');
		if (target) {
			target.focus();
		}
	}

	function closeDialog(dialog) {
		if (!dialog) {
			return;
		}
		if (typeof dialog.close === 'function') {
			dialog.close();
		} else {
			dialog.removeAttribute('open');
		}
		const opener = dialogOpeners.get(dialog);
		if (opener && typeof opener.focus === 'function' && document.contains(opener)) {
			opener.focus();
		}
	}

	function bindDialogDismiss(root) {
		root.querySelectorAll('[data-dialog-close]').forEach(function (button) {
			button.addEventListener('click', function () {
				closeDialog(button.closest('dialog'));
			});
		});
		root.querySelectorAll('dialog').forEach(function (dialog) {
			dialog.addEventListener('click', function (event) {
				if (event.target === dialog) {
					closeDialog(dialog);
				}
			});
		});
	}

	function debounce(callback, delay) {
		let timeout;
		return function () {
			const args = arguments;
			window.clearTimeout(timeout);
			timeout = window.setTimeout(() => callback.apply(null, args), delay);
		};
	}

	function dateKey(date) {
		const year = date.getFullYear();
		const month = String(date.getMonth() + 1).padStart(2, '0');
		const day = String(date.getDate()).padStart(2, '0');
		return `${year}-${month}-${day}`;
	}

	function dateKeyInTimeZone(date, timeZone) {
		const parsed = asDate(date);
		if (!parsed) {
			return '';
		}
		try {
			const parts = new Intl.DateTimeFormat('en-CA', {
				timeZone: timeZone || undefined, year: 'numeric', month: '2-digit', day: '2-digit',
			}).formatToParts(parsed);
			const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
			return `${values.year}-${values.month}-${values.day}`;
		} catch (_error) {
			return dateKey(parsed);
		}
	}

	function list(value) {
		return Array.isArray(value) ? value : [];
	}

	window.AppointmentsUI = Object.freeze({
		appendChildren,
		bindDialogDismiss,
		clear,
		closeDialog,
		dateKey,
		dateKeyInTimeZone,
		debounce,
		element,
		formatDate,
		formatDateTime,
		formatMoney,
		formatTime,
		formatTimeWithZone,
		list,
		locale,
		option,
		request,
		safeUrl,
		showDialog,
		statusLabel,
		translate,
	});
}());
