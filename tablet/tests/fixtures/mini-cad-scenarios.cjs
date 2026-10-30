// Synthetic data shared by the browser checks and local visual review gallery.
const defaultIdent = 42;

function makeCall(overrides = {}) {
    return {
        dispatch_type: 'CALL_NEW',
        dispatch: {
            callId: 1024,
            code: '10-50',
            title: 'Traffic collision',
            postal: '7253',
            address: 'Alta St / San Andreas Ave',
            description: 'Two vehicles are blocking the intersection. Responding units requested.',
            notes: [{ type: 'text', time: '14:36', label: 'Dispatch', content: 'Caller reports minor injuries.' }],
            units: ['1A-12', 'ENGINE 3'].map(unitNum => ({ data: { unitNum } })),
            idents: [],
            ...overrides
        }
    };
}

const longCode = 'SPECIAL RESPONSE / MULTI AGENCY OPERATIONS / EXTENDED CUSTOM DISPATCH CODE';
const longTitle = 'Multiple vehicles involved in a collision with a commercial delivery truck and debris blocking all eastbound lanes near the shopping center entrance';
const longAddress = 'Eastbound San Andreas Avenue at the lower service road entrance to the Metropolitan Shopping and Transit Center, opposite the north parking structure';
const literal = '<img src=x onerror="window.__miniInjected=true"> & <b>literal CAD text</b>';

const scenarios = {
    normal: {
        label: 'Normal call',
        calls: [makeCall(), makeCall({ callId: 1025, code: '10-66', title: 'Suspicious person', address: 'Vespucci Blvd', units: [] })]
    },
    attached: {
        label: 'Attached to the selected call',
        calls: [makeCall({ idents: [defaultIdent] })]
    },
    long_header: {
        label: 'Long custom code, title and address',
        calls: [makeCall({ code: longCode, title: longTitle, address: longAddress })]
    },
    unbroken: {
        label: 'Unbroken custom text',
        calls: [makeCall({
            code: 'ÉVÉNEMENT 🚒\nCUSTOMCODE_' + 'X'.repeat(160) + '_ENDCODE',
            title: '事故通報 🚓\nEXTENDEDTITLE_' + 'TITLE'.repeat(65) + '_ENDTITLE',
            address: '通り / Straße\nUNBROKENADDRESS_' + 'ROAD'.repeat(75) + '_ENDADDRESS',
            units: [{ data: { unitNum: '特殊部隊 🚓 LONGUNIT_' + '9'.repeat(160) } }]
        })]
    },
    many_units: {
        label: 'Many units and long unit labels',
        calls: [makeCall({ units: Array.from({ length: 48 }, (_, i) => ({
            data: { unitNum: i % 3 === 0 ? `SPECIAL-RESPONSE-COMMAND-UNIT-${i + 1}-` + 'A'.repeat(70) : `UNIT ${i + 1}` }
        })) })]
    },
    no_units: {
        label: 'No attached units',
        calls: [makeCall({ units: [] })]
    },
    long_details: {
        label: 'Long multiline description and recent notes',
        details: true,
        notesRows: 6,
        calls: [makeCall({
            code: longCode,
            title: longTitle,
            address: longAddress,
            description: Array.from({ length: 80 }, (_, i) => `Line ${i + 1}: Responding units should use the east service road and coordinate with dispatch.\nREFERENCE_${'LONG'.repeat(20)}`).join('\n') + '\nDESCRIPTION-END-MARKER',
            notes: Array.from({ length: 20 }, (_, i) => ({
                type: 'text', time: `14:${String(i).padStart(2, '0')}`, label: 'Dispatch',
                content: i === 14 ? 'OLDEST-VISIBLE-NOTE-END-MARKER' : `Recent note ${i + 1}: ${i === 19 ? 'LATEST-NOTE-MARKER' : 'Coordinate the response.'}`
            }))
        })]
    },
    attachments: {
        label: 'Recent notes, attachment, legacy and literal HTML text',
        details: true,
        notesRows: 6,
        calls: [makeCall({
            code: 'CODE ' + literal,
            title: 'Literal call title ' + literal,
            address: 'Literal address ' + literal,
            description: 'This must remain plain text:\n' + literal,
            units: [{ data: { unitNum: 'UNIT ' + literal } }],
            notes: [
                { type: 'text', time: '13:00', label: 'Dispatch', content: 'HIDDEN-OLD-NOTE-MARKER' },
                { type: 'text', time: '13:01', label: 'Dispatch', content: 'Second old note' },
                'Legacy note: ' + literal,
                { type: 'image', time: '14:01', label: 'Dispatcher A', content: 'attachment-example.png' },
                { type: 'text', time: '14:02', label: 'Sonoran CAD', content: 'System note without a redundant label.' },
                { type: 'text', time: '14:03', label: 'Dispatcher B', content: literal },
                { type: 'text', time: '14:04', label: 'Dispatch', content: 'Penultimate recent note' },
                { type: 'text', time: '14:05', label: 'Dispatch', content: 'LATEST-LITERAL-NOTE-MARKER' }
            ]
        })]
    },
    empty: {
        label: 'No active calls',
        calls: []
    }
};

module.exports = { scenarios, makeCall, defaultIdent, literal };
